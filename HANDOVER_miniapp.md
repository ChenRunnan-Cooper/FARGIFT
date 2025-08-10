# Handover for MiniAPP 组 – 日志索引与礼物内容可视化

本文面向 MiniAPP 端同学，说明如何基于合约事件（Logs）与只读查询，完成“礼物列表/详情”的前端渲染与实时订阅。整体遵循零权限、只读、安全可恢复的模式，适配本地 fork、测试网与后续主网迁移。

## 背景与职责边界
- 合约：`Present.sol`（Solidity ^0.8.20）
  - 核心事件（生产）：
    - `event WrapPresent(bytes32 indexed presentId, address sender)`
    - `event UnwrapPresent(bytes32 indexed presentId, address taker)`
    - `event TakeBack(bytes32 indexed presentId, address sender)`
  - 核心事件（测试部署推荐使用，避免暴露正式 selector）：
    - `event WrapPresentTest(bytes32 indexed presentId, address sender)`
    - `event UnwrapPresentTest(bytes32 indexed presentId, address taker)`
    - `event TakeBackTest(bytes32 indexed presentId, address sender)`
  - 只读查询（聚合）：`getPresent(bytes32)` 返回 sender、recipients、content、title、description、status、expiryAt
  - 兼容查询：`getPresentContent(bytes32)`、`getPresentStatus(bytes32)`
- 你们负责：
  - 从 Logs 中提取 `presentId`，回放历史 + 订阅实时新增；
  - 通过 `getPresent(presentId)` 拉取元信息（含 content）渲染；必要时再调用独立只读；
  - 维护本地状态：礼物清单、当前状态（活跃/已拆/已收回/已过期）、资产清单、最近交易；
  - 不进行任何写操作与签名操作。

## 网络与合约地址
- ChainId：Arbitrum Sepolia = `421614`
- 测试网地址（已部署）：
  - Present: `0x3B3cF7ee8dbCDDd8B8451e38269D982F351ca3db`
  - WrappedPresentNFT: `0x8260BB51092F058F4f234407f1075f09ab5832c9`
  - UnwrappedPresentNFT: `0x22F2800aeE94c9e57D76981bC13e7a3760D396D9`
- ABI 文件（仓库已提供）：
  - `abi/Present.json`
  - `abi/WrappedPresentNFT.json`
  - `abi/UnwrappedPresentNFT.json`
- 重要关系：`tokenId = uint256(presentId)`（NFT 与礼物一一对应）

## 事件主题（Topics）与编码
- 事件签名（ethers v6）：
```ts
import { id as keccak256 } from "ethers";
const WRAP_T = keccak256("WrapPresentTest(bytes32,address)");
const UNWRAP_T = keccak256("UnwrapPresentTest(bytes32,address)");
const TAKEBACK_T = keccak256("TakeBackTest(bytes32,address)");
// 若未来切换到生产事件：
const WRAP = keccak256("WrapPresent(bytes32,address)");
const UNWRAP = keccak256("UnwrapPresent(bytes32,address)");
const TAKEBACK = keccak256("TakeBack(bytes32,address)");
```
- 索引字段：`presentId` 为 indexed → `topics[1]`；地址参数未 indexed → 位于 data（标准 ABI 解码）。

## 最小 ABI（只读，推荐）
```ts
export const PRESENT_MIN_ABI = [
  "event WrapPresentTest(bytes32 indexed presentId, address sender)",
  "event UnwrapPresentTest(bytes32 indexed presentId, address taker)",
  "event TakeBackTest(bytes32 indexed presentId, address sender)",
  "function getPresent(bytes32 presentId) view returns (address,address[],(address,uint256)[],string,string,uint8,uint256)",
];
```

## 历史日志回放（HTTP getLogs）
- 以 `WrapPresentTest` 作为“新增礼物”；`UnwrapPresentTest/TakeBackTest` 更新状态。
- 示例：
```ts
import { ethers } from "ethers";

async function fetchLogs({ rpcUrl, contract, fromBlock, toBlock }) {
  const provider = new ethers.JsonRpcProvider(rpcUrl);
  const topics = [
    ethers.id("WrapPresentTest(bytes32,address)"),
    ethers.id("UnwrapPresentTest(bytes32,address)"),
    ethers.id("TakeBackTest(bytes32,address)"),
  ];
  const logs = [];
  for (const t of topics) {
    const l = await provider.getLogs({ address: contract, topics: [t], fromBlock, toBlock });
    logs.push(...l);
  }
  logs.sort((a, b) => (a.blockNumber - b.blockNumber) || (a.index - b.index));
  return logs;
}
```
- 分段抓取/失败重试/幂等键（三元组）同原文建议。

## 实时订阅（WebSocket）
与原文相同，切换为 `*Test` 事件签名。

## 日志解析与数据模型
- `presentId = log.topics[1]`
- 地址参数：`ethers.AbiCoder.defaultAbiCoder().decode(["address"], log.data)`
- 本地模型：`presentId -> { status, assets, title, desc, expiryAt, createdAt, txs[] }`

## 合约只读调用 – 展示礼物
- 推荐一次性读取聚合：
```ts
import { ethers } from "ethers";
const iface = new ethers.Interface(PRESENT_MIN_ABI);
const data = iface.encodeFunctionData("getPresent", [presentId]);
const ret = await provider.call({ to: presentAddress, data });
const [sender, recipients, content, title, desc, status, expiryAt] = iface.decodeFunctionResult("getPresent", ret);
```
- 若只需资产：继续支持 `getPresentContent(bytes32)`。

## 本地 fork（零成本）联调
沿用 README 步骤，端点：
- HTTP：`http://127.0.0.1:8547`
- WSS：`ws://127.0.0.1:8547`

## UI/数据建议
沿用原文，新增：
- 展示 `title/description`；
- `status` 含义：0 active / 1 unwrapped / 2 takenBack / 3 expired。

## 错误恢复与鲁棒性
沿用原文建议。

## 环境变量建议（前端 .env）
```env
VITE_CHAIN_ID=421614
VITE_PRESENT_ADDRESS=0x3B3cF7ee8dbCDDd8B8451e38269D982F351ca3db
VITE_RPC_HTTP=https://arb-sepolia.g.alchemy.com/v2/<KEY>
VITE_RPC_WSS=wss://arb-sepolia.g.alchemy.com/v2/<KEY>
```

## 验收清单
- [ ] 回放 `WrapPresentTest`，presentId 可解析；
- [ ] `getPresent` 可读取并渲染 title/desc/content/status；
- [ ] 订阅 `UnwrapPresentTest/TakeBackTest`，状态可更新；
- [ ] 本地 fork 与测试网均通过自测。

## Cast 快速核对
```bash
# 取某交易 presentId（WrapPresentTest 的 indexed 参数）
TX=0x<txHash>
cast receipt $TX --rpc-url "$ARBITRUM_SEPOLIA_RPC_URL"

# 读取礼物聚合信息
cast call 0x3B3cF7ee8dbCDDd8B8451e38269D982F351ca3db \
  "getPresent(bytes32)((address,address[],(address,uint256)[],string,string,uint8,uint256))" \
  0x<PRESENT_ID> \
  --rpc-url "$ARBITRUM_SEPOLIA_RPC_URL"

# 读取 Wrapped NFT tokenURI
cmp <(echo 0x<PRESENT_ID>) <(cast keccak 0x<PRESENT_ID>) >/dev/null 2>&1 || true
cast call 0x8260BB51092F058F4f234407f1075f09ab5832c9 "tokenURI(uint256)" 0x<PRESENT_ID> \
  --rpc-url "$ARBITRUM_SEPOLIA_RPC_URL"
``` 