# FarGift

一个“链上送礼”系统：把 ETH / ERC20 打包成礼物（wrap），支持定向或公开领取（unwrap），支持寄件人收回（takeBack），并用两类 ERC721 作为状态凭证（Wrapped/Unwrapped）。部署目标：Arbitrum Sepolia（chainId 421614）。

---

## 网络与合约地址（测试网，拿来即用）
- 链：Arbitrum Sepolia（chainId 421614）
- Present 合约地址（统一使用此地址聚合样例与订阅）：
  - 0x3B3cF7ee8dbCDDd8B8451e38269D982F351ca3db
- 一键导出到环境变量（可直接粘贴到终端）：
  ```bash
  export ARBITRUM_SEPOLIA_RPC_URL="https://<你的RPC>"
  export PRIVATE_KEY="0x<你的测试网私钥>"
  export PRESENT_ADDRESS="0x3B3cF7ee8dbCDDd8B8451e38269D982F351ca3db"
  ```

---

## 目录结构（精简但高信噪）

```
FarGift/
├─ abi/                             # ABI（已整理为可编程 vs 可阅读）
│  ├─ raw/                          # 给 miniapp/后端直接用的“纯 ABI 数组”
│  │  ├─ Present.abi.json
│  │  ├─ WrappedPresentNFT.abi.json
│  │  └─ UnwrappedPresentNFT.abi.json
│  └─ table/                        # 人类可读的表格样式（仅浏览，不建议程序使用）
│     ├─ Present.json
│     ├─ WrappedPresentNFT.json
│     └─ UnwrappedPresentNFT.json
├─ broadcast/                       # Foundry 广播产物（含每笔交易与事件快照）
│  ├─ DeployPresent.s.sol/
│  ├─ GenerateSamplesOnExisting.s.sol/
│  ├─ WrapOnly.s.sol/
│  └─ WrapWithERC20.s.sol/
├─ script/                          # 部署与样例数据脚本
│  ├─ DeployPresent.s.sol           # 部署 Present
│  ├─ DeployNFTs.s.sol              # 部署两类 NFT 并绑定到 Present
│  ├─ GenerateSamples.s.sol         # 新部署 + 批量样例（A/B/C/D）
│  ├─ GenerateSamplesOnExisting.s.sol# 在已部署地址上追加样例（推荐日志统一地址）
│  ├─ WrapOnly.s.sol                # 仅 wrap ETH（可配置公开/定向）
│  └─ WrapWithERC20.s.sol           # 自动部署/使用 ERC20 -> approve -> wrapPresentTest
├─ src/
│  ├─ Present.sol                   # 核心合约：wrap / unwrap / takeBack / 状态与风控
│  └─ nft/
│     ├─ WrappedPresentNFT.sol      # 已打包凭证 NFT（tokenId = uint256(presentId)）
│     └─ UnwrappedPresentNFT.sol    # 已拆包凭证 NFT
├─ test/
│  ├─ Present.t.sol                 # Present 单测
│  └─ mocks/MockERC20.sol           # 测试用简单 ERC20
├─ HANDOVER_miniapp.md              # 给 miniapp / farcaster 组的实践说明（订阅事件+只读查询）
├─ foundry.toml / env.example       # Foundry 与环境变量模板
└─ README.md                        # 当前文件
```

---

## 环境准备

- 安装 Foundry
  ```bash
  curl -L https://foundry.paradigm.xyz | bash
  foundryup
  ```
- 配置 `.env`（基于 `env.example`）
  ```bash
  cp env.example .env
  # 编辑 .env，填入：
  # ARBITRUM_SEPOLIA_RPC_URL=...
  # PRIVATE_KEY=0x<测试网私钥>
  ```
- 编译
  ```bash
  forge clean && forge build
  ```

---

## ABI 在哪里（miniapp/后端用）

- 可编程的“纯 ABI 数组”：请使用 `abi/raw/*.abi.json`
  - `abi/raw/Present.abi.json`
  - `abi/raw/WrappedPresentNFT.abi.json`
  - `abi/raw/UnwrappedPresentNFT.abi.json`
- 人类可读（表格样式）：`abi/table/*.json`（仅用于浏览，不建议程序引用）

---

## 在测试网上批量生成样例数据（给 Farcaster/miniapp 用的 Logs）

下面两种方式二选一：

### 方式 A：在“已有的 Present 地址”上追加样例（推荐：日志集中在一个地址）

1) 导出环境变量
```bash
export ARBITRUM_SEPOLIA_RPC_URL="https://<你的RPC>"
export PRIVATE_KEY="0x<你的测试网私钥>"
export PRESENT_ADDRESS="0x3B3cF7ee8dbCDDd8B8451e38269D982F351ca3db"
```
2) 批量产出 4 组 ETH 样例（A/B/C/D）
```bash
forge script script/GenerateSamplesOnExisting.s.sol:GenerateSamplesOnExisting \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast --skip-simulation
```
3) 仅追加“wrap ETH 一次”（快速补数据，可选）
```bash
forge script script/WrapOnly.s.sol:WrapOnly \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast --skip-simulation
```
4) 追加“ERC20 礼物”样例（自动部署 MockERC20 → mint → approve → wrapPresentTest）
```bash
# 如有现成测试 ERC20，可先：export TOKEN_ADDRESS=0x<ERC20地址>
forge script script/WrapWithERC20.s.sol:WrapWithERC20 \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast --skip-simulation
```
5) 结果在哪里
- 本地广播快照（含每笔交易与事件解码）：
  - `broadcast/GenerateSamplesOnExisting.s.sol/421614/run-latest.json`
  - `broadcast/WrapOnly.s.sol/421614/run-latest.json`
  - `broadcast/WrapWithERC20.s.sol/421614/run-latest.json`
- 链上权威数据：
  - 用区块浏览器或 RPC，查询 `PRESENT_ADDRESS` 的事件：
    - `WrapPresent(bytes32,address)`
    - `UnwrapPresent(bytes32,address)`
    - `TakeBack(bytes32,address)`
    - （ERC20 测试脚本用的是 `wrapPresentTest`，对应 `WrapPresentTest` 事件）

### 方式 B：新部署 + 一次性生成样例

```bash
forge script script/GenerateSamples.s.sol:GenerateSamples \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast --skip-simulation
# 控制台会打印新 Present 地址；样例同上（A:wrap->unwrap / B:wrap->takeBack / C:公开->unwrap / D:保持ACTIVE）
```

---

## miniapp / farcaster 快速接入（只需合约地址 + ABI + 链信息）

- 链：Arbitrum Sepolia（chainId 421614）
- 合约地址：统一使用 `0x3B3cF7ee8dbCDDd8B8451e38269D982F351ca3db`
- ABI：`abi/raw/Present.abi.json`

监听事件（以 viem 为例）
```ts
import { createPublicClient, http } from 'viem';
import { arbitrumSepolia } from 'viem/chains';
import presentAbi from './abi/raw/Present.abi.json';

const client = createPublicClient({ chain: arbitrumSepolia, transport: http(process.env.RPC_URL) });
const PRESENT = '0x3B3cF7ee8dbCDDd8B8451e38269D982F351ca3db';

client.watchContractEvent({ address: PRESENT, abi: presentAbi, eventName: 'WrapPresent', onLogs: logs => {/* logs[i].args.presentId */} });
client.watchContractEvent({ address: PRESENT, abi: presentAbi, eventName: 'UnwrapPresent', onLogs: logs => {} });
client.watchContractEvent({ address: PRESENT, abi: presentAbi, eventName: 'TakeBack', onLogs: logs => {} });
// 如使用 wrapPresentTest 入口，还可监听 WrapPresentTest
```
读取礼物详情（getPresent）
```ts
import { getContract } from 'viem';
const present = getContract({ address: PRESENT, abi: presentAbi, client });
const [sender, recipients, content, title, desc, status, expiryAt] = await present.read.getPresent([presentId]);
```
要点：
- `presentId` 从事件 args 获取；`tokenId = uint256(presentId)`（两个 NFT 的 tokenId 对应同一礼物）
- ABI 只定义事件/函数形状，不包含历史日志；历史日志存链上，按地址/事件订阅或 getLogs 即可

---

## 常见问题
- 为什么要先 `approve` 再 wrap ERC20？
  - 因为合约会调用 `transferFrom` 把代币从你地址托管到合约，需要你先授权额度
- `WrapPresent` vs `WrapPresentTest`？
  - 逻辑一致，后者带元数据（title/description），便于测试展示；生产可只用前者
- 要不要把“日志文件”发给前端？
  - 不需要。miniapp/farcaster 直接从链上按 `PRESENT_ADDRESS` 订阅/拉取；`broadcast/` 仅供本地对照

---

## 变更历史（本次整理）
- 新增脚本：`GenerateSamplesOnExisting.s.sol`、`WrapOnly.s.sol`、`WrapWithERC20.s.sol`
- 整理 ABI 目录：`abi/raw`（纯 ABI）、`abi/table`（可读表）
- 补充测试网样例生成与 miniapp/farcaster 接入说明
