# Handover for MiniAPP 组 – 日志索引与礼物内容可视化

本文面向 MiniAPP 端同学，说明如何基于合约事件（Logs）与只读查询，完成“礼物列表/详情”的前端渲染与实时订阅。整体遵循零权限、只读、安全可恢复的模式，适配本地 fork、测试网与后续主网迁移。

## 背景与职责边界
- 合约：`Present.sol`（Solidity ^0.8.20）
  - 核心事件（固定接口，不可改）：
    - `event WrapPresent(bytes32 indexed presentId, address sender)`
    - `event UnwrapPresent(bytes32 indexed presentId, address taker)`
    - `event TakeBack(bytes32 indexed presentId, address sender)`
  - 只读查询：
    - `getPresentContent(bytes32)((address tokens,uint256 amounts)[])`
    - （可选，如存在）`getPresentStatus(bytes32) -> uint8`
- 你们负责：
  - 从 Logs 中提取 `presentId`，回放历史 + 订阅实时新增；
  - 通过只读 ABI 调用 `getPresentContent(presentId)` 拉取礼物内容渲染；
  - 维护本地状态：礼物清单、当前状态（活跃/已拆/已收回）、资产清单、最近交易；
  - 不进行任何写操作与签名操作。

## 运行环境与网络
- 推荐网络（按研发阶段）：
  1) 本地 fork（零成本）– 强烈推荐联调：`http://127.0.0.1:8547` / `ws://127.0.0.1:8547`
  2) Arbitrum Sepolia（测试网）– 需稳定 RPC（Alchemy/Infura），HTTP 与 WSS 双通道
- ChainId：Arbitrum Sepolia = `421614`
- 合约地址：
  - 开发联调：按《README.md – 本地 fork 仿真》步骤在本地部署后，使用当次输出的合约地址；
  - 公网测试：待合约组部署后提供固定地址。

## 事件主题（Topics）与编码
- 事件签名（建议在代码中计算，避免硬编码）：
  ```ts
  import { id as keccak256 } from "ethers"; // ethers v6
  const WRAP_TOPIC0 = keccak256("WrapPresent(bytes32,address)");
  const UNWRAP_TOPIC0 = keccak256("UnwrapPresent(bytes32,address)");
  const TAKEBACK_TOPIC0 = keccak256("TakeBack(bytes32,address)");
  ```
- 索引字段：`presentId` 为 indexed → 出现在 `topics[1]`；第二个地址参数未 indexed → 位于 data（0x 编码，标准 ABI 规则）。
- 解码地址：可用 `ethers.AbiCoder.defaultAbiCoder().decode(["address"], data)`。

## 最小 ABI（只读）
```ts
export const PRESENT_ABI = [
  "event WrapPresent(bytes32 indexed presentId, address sender)",
  "event UnwrapPresent(bytes32 indexed presentId, address taker)",
  "event TakeBack(bytes32 indexed presentId, address sender)",
  "function getPresentContent(bytes32 presentId) view returns ((address tokens,uint256 amounts)[])",
  // 可选：若合约提供
  "function getPresentStatus(bytes32 presentId) view returns (uint8)",
];
```

## 历史日志回放（HTTP getLogs）
- 目的：首次加载时构建“礼物库”：
  - 以 `WrapPresent` 作为“新增礼物”的信号；
  - 以 `UnwrapPresent`、`TakeBack` 更新状态。
- 参考代码（ethers v6）：
```ts
import { ethers } from "ethers";

async function fetchLogs({ rpcUrl, contract, fromBlock, toBlock }) {
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const filters = [
    { address: contract, topics: [ethers.id("WrapPresent(bytes32,address)")] },
    { address: contract, topics: [ethers.id("UnwrapPresent(bytes32,address)")] },
    { address: contract, topics: [ethers.id("TakeBack(bytes32,address)")] },
  ];
  const results = [];
  for (const f of filters) {
    const logs = await provider.getLogs({ ...f, fromBlock, toBlock });
    results.push(...logs);
  }
  // 排序：按区块/交易索引
  results.sort((a, b) => (a.blockNumber - b.blockNumber) || (a.index - b.index));
  return results;
}
```
- 分段抓取：对大范围区块，按区间分页，失败重试与指数退避，避免 RPC 限流。
- 幂等性：用 `(blockNumber, transactionHash, logIndex)` 作为唯一键，去重。

## 实时订阅（WebSocket）
- 目的：页面与榜单实时更新；
- 参考代码：
```ts
import { ethers } from "ethers";

export function subscribeLogs({ wssUrl, contract, onEvent }) {
  const provider = new ethers.WebSocketProvider(wssUrl);
  const topics = [
    ethers.id("WrapPresent(bytes32,address)"),
    ethers.id("UnwrapPresent(bytes32,address)"),
    ethers.id("TakeBack(bytes32,address)")
  ];
  for (const t of topics) {
    const filter = { address: contract, topics: [t] };
    provider.on(filter, (log) => onEvent(log));
  }
  provider._websocket?.on("close", () => {
    // 简单重连策略（建议引入成熟重连库）
    setTimeout(() => subscribeLogs({ wssUrl, contract, onEvent }), 1500);
  });
  return () => provider.destroy();
}
```

## 日志解析与数据模型
- 解析：
  ```ts
  import { ethers } from "ethers";
  const coder = ethers.AbiCoder.defaultAbiCoder();

  function parseLog(log) {
    const topic0 = log.topics[0];
    const presentId = log.topics[1]; // indexed bytes32
    let actor: string | undefined;
    if (topic0 === ethers.id("WrapPresent(bytes32,address)")) {
      [actor] = coder.decode(["address"], log.data);
      return { kind: "wrap", presentId, actor, ...pos(log) };
    }
    if (topic0 === ethers.id("UnwrapPresent(bytes32,address)")) {
      [actor] = coder.decode(["address"], log.data);
      return { kind: "unwrap", presentId, actor, ...pos(log) };
    }
    if (topic0 === ethers.id("TakeBack(bytes32,address)")) {
      [actor] = coder.decode(["address"], log.data);
      return { kind: "takeback", presentId, actor, ...pos(log) };
    }
    return undefined;
  }
  function pos(l){ return { blockNumber: l.blockNumber, txHash: l.transactionHash, logIndex: l.index } }
  ```
- 本地存储建议（以 Map/数据库存放）：
  - `presentId -> { status, assets, createdAt, lastEvent, txs[] }`
  - `status`：缺省 active → `unwrap` 改为 unwrapped → `takeback` 改为 takenBack
  - `assets`：首次 `wrap` 后通过合约读取并缓存

## 合约只读调用 – 展示礼物内容
- 读取资产：
```ts
import { ethers } from "ethers";

export async function readContent({ rpcUrl, contract, presentId }) {
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const iface = new ethers.Interface(PRESENT_ABI);
  const data = iface.encodeFunctionData("getPresentContent", [presentId]);
  const ret = await provider.call({ to: contract, data });
  const [assets] = iface.decodeFunctionResult("getPresentContent", ret);
  // assets: Array<{ tokens: string, amounts: bigint }>
  return assets;
}
```
- （可选）读取状态：
```ts
export async function readStatus({ rpcUrl, contract, presentId }) {
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const iface = new ethers.Interface(PRESENT_ABI);
  try {
    const data = iface.encodeFunctionData("getPresentStatus", [presentId]);
    const ret = await provider.call({ to: contract, data });
    const [status] = iface.decodeFunctionResult("getPresentStatus", ret);
    return Number(status); // 0 活跃/1 已拆/2 已收回/3 已过期（以合约为准）
  } catch { return undefined; }
}
```

## 本地 fork（零成本）联调步骤（强烈推荐）
1) 启动本地 anvil（fork Arbitrum Sepolia，端口 8547）：
   ```bash
   anvil --fork-url https://arb-sepolia.g.alchemy.com/v2/<YOUR_KEY> --chain-id 421614 --port 8547
   ```
2) 注资部署地址（示例地址见 README）：
   ```bash
   cast rpc anvil_setBalance 0x<DEPLOYER> 0xDE0B6B3A7640000 --rpc-url http://127.0.0.1:8547
   ```
3) 部署与一次 wrap（详见 README“本地 fork 仿真”）：
   ```bash
   forge script script/DeployPresent.s.sol:DeployPresent --rpc-url http://127.0.0.1:8547 --private-key "$PRIVATE_KEY" --broadcast
   export PRESENT_ADDRESS=0x<输出合约地址>
   forge script script/DeployPresent.s.sol:TestPresentCalls --rpc-url http://127.0.0.1:8547 --private-key "$PRIVATE_KEY" --broadcast
   ```
4) MiniAPP 指向本地节点：
   - HTTP：`http://127.0.0.1:8547`（历史回放）
   - WSS：`ws://127.0.0.1:8547`（实时订阅）
5) 用本地合约地址做一次全流程：
   - 回放历史 `WrapPresent`，解析 `presentId`；
   - 调 `getPresentContent` 拉取资产；
   - 订阅 `UnwrapPresent/TakeBack`，观察状态更新。

## UI/数据与展示建议
- 列表字段：金额合计（ETH + ERC20 估值可后续补做）、资产条数、最近事件、presentId（短码展示）；
- 详情页：资产清单（token 符号/地址、数量）、状态、交易时间线；
- presentId：可点击复制（0x…）；
- 性能：
  - 首屏仅回放最近 N 块或最近 M 条；
  - 懒加载更早历史；
  - 为 getLogs 做分页与并发窗口控制（如 5–10 并发）。

## 错误恢复与鲁棒性
- getLogs 返回超限/429：缩小区间 + 指数退避；
- WebSocket 断线：指数回退重连；
- Reorg：以 `(blockNumber, txHash, logIndex)` 作为幂等键，且对同一 presentId 允许状态回滚（少见，测试网更常见）；
- 非标准 ERC20：仅影响估值/符号展示，不影响资产地址与数量；
- JSON-RPC 限流：预留多 RPC Fallback（`ARBITRUM_SEPOLIA_RPC_URLS`）。

## 环境变量建议（前端 .env）
```
VITE_CHAIN_ID=421614
VITE_PRESENT_ADDRESS=0x<合约地址>
VITE_RPC_HTTP=http://127.0.0.1:8547
VITE_RPC_WSS=ws://127.0.0.1:8547
# 可选公网
# VITE_RPC_HTTP=https://arb-sepolia.g.alchemy.com/v2/<KEY>
# VITE_RPC_WSS=wss://arb-sepolia.g.alchemy.com/v2/<KEY>
```

## 联调验收清单
- [ ] 历史回放：近 N 区块内能抓到 `WrapPresent` 并显示礼物；
- [ ] 实时订阅：新 `WrapPresent` 能秒级出现在列表；
- [ ] 详情页：`getPresentContent(presentId)` 能展示资产明细；
- [ ] 状态联动：`UnwrapPresent/TakeBack` 到来后，状态更新；
- [ ] 本地 fork 自测：按 README 流程可从 0 到 1；
- [ ] 异常网络下可自动恢复（断线重连/限流退避）。

## 附：Cast 快速核对命令
```bash
# 取某交易的 presentId（WrapPresent 的 indexed 参数）
TX=0x<txHash>
cast receipt $TX --rpc-url http://127.0.0.1:8547 | jq -r \
  '.logs[] | select(.topics[0]=="'$(cast keccak "WrapPresent(bytes32,address)")'") | .topics[1]'

# 读取礼物内容
cast call $VITE_PRESENT_ADDRESS \
  "getPresentContent(bytes32)((address,uint256)[])" 0x<PRESENT_ID> \
  --rpc-url http://127.0.0.1:8547
```

如需扩展更多前端字段（如接收者、过期时间、是否公开/定向），可在仅依赖只读接口的前提下按需增加查询；若涉及新增合约只读方法，请与合约组确认后再行实现。 