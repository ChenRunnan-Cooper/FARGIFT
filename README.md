# FarGift

一个功能丰富的“链上送礼”系统。除了基础的“打包/领取/收回”功能，还支持多种礼物分配模式：**先到先得**、**限量均分**、**白名单均分**与**随机红包**。系统通过两类 ERC721 作为状态凭证（Wrapped/Unwrapped）。部署在 Arbitrum Sepolia（chainId 421614）。

---

## 网络与合约地址（测试网，拿来即用）
- 链：Arbitrum Sepolia（chainId 421614）
- Present 合约地址（统一使用此地址聚合样例与订阅）：
  - 0x8cED4381845b1fB450C8D2279ed4c888A38fC08d
- 一键导出到环境变量（可直接粘贴到终端）：
  ```bash
  export ARBITRUM_SEPOLIA_RPC_URL="https://<你的RPC>"
  export PRIVATE_KEY="0x<你的测试网私钥>"
  export PRESENT_ADDRESS="0x8cED4381845b1fB450C8D2279ed4c888A38fC08d"
  ```

---

## 核心概念：多样的礼物分配模式

合约通过一个统一的、功能强大的 `wrapPresent` 函数来创建所有类型的礼物。您可以通过调整其参数来激活不同的分配模式：

| 模式 | `DistributionType` 参数 | 关键参数说明 |
| :--- | :--- | :--- |
| **先到先得** | `FIRST_COME_FIRST_SERVED` | **经典模式**：整个礼物由一个符合条件的接收人一次性领取。若 `recipients` 列表为空，则任何人可领。`claimLimit` 会被忽略。 |
| **限量均分** | `LIMITED_QUANTITY_EQUAL_SPLIT` | **公开红包**：礼物总额被均分为 N 份。创建时需在 `claimLimit` 中指定 N，并保持 `recipients` 列表为空。 |
| **白名单均分**| `WHITELIST_EQUAL_SPLIT` | **定向空投**：礼物总额按 `recipients` 白名单的人数均分。合约会自动忽略 `claimLimit`，并使用名单长度作为上限。 |
| **限量随机** | `LIMITED_QUANTITY_RANDOM_SPLIT`| **随机红包**：创建时需在 `prizeTiers` 中定义一个“奖池”，合约会据此计算总名额。`recipients` 需为空。 |

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
│  ├─ GenerateSamples.s.sol         # 【推荐】新部署 + 批量生成各类模式的样例
│  ├─ GenerateSamplesOnExisting.s.sol# 在已部署地址上追加样例
│  ├─ WrapOnly.s.sol                # 仅 wrap ETH（经典模式）
│  └─ WrapWithERC20.s.sol           # 自动部署/使用 ERC20 -> approve -> wrap
├─ src/
│  ├─ Present.sol                   # 核心合约：支持多种分配模式的 wrap / claim / takeBack
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
- 编译与测试
```bash
  forge clean && forge build && forge test
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
export PRESENT_ADDRESS="0x8cED4381845b1fB450C8D2279ed4c888A38fC08d"
```
2) 批量产出 **多种模式** 的 ETH 样例
```bash
forge script script/GenerateSamplesOnExisting.s.sol:GenerateSamplesOnExisting \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast --skip-simulation
```
3) 追加“ERC20 礼物”样例（自动部署 MockERC20 → mint → approve → wrap）
```bash
# 如有现成测试 ERC20，可先：export TOKEN_ADDRESS=0x<ERC20地址>
forge script script/WrapWithERC20.s.sol:WrapWithERC20 \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast --skip-simulation
```
4) 结果在哪里
- 本地广播快照（含每笔交易与事件解码）：
  - `broadcast/GenerateSamplesOnExisting.s.sol/421614/run-latest.json`
  - `broadcast/WrapWithERC20.s.sol/421614/run-latest.json`
- 链上权威数据：
  - 用区块浏览器或 RPC，查询 `PRESENT_ADDRESS` 的事件：
    - `WrapPresent(bytes32,address)`
    - `UnwrapPresent(bytes32,address)`
    - `TakeBack(bytes32,address)`

### 方式 B：新部署 + 一次性生成所有样例

```bash
forge script script/GenerateSamples.s.sol:GenerateSamples \
  --rpc-url $ARBITRUM_SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast --skip-simulation
# 控制台会打印新 Present 地址；脚本会生成覆盖所有分配模式的样例
```

---

## miniapp / farcaster 快速接入（只需合约地址 + ABI + 链信息）

- 链：Arbitrum Sepolia（chainId 421614）
- 合约地址：统一使用 `0x8cED4381845b1fB450C8D2279ed4c888A38fC08d`
- ABI：`abi/raw/Present.abi.json`

**监听事件**（以 viem 为例）
```ts
import { createPublicClient, http } from 'viem';
import { arbitrumSepolia } from 'viem/chains';
import presentAbi from './abi/raw/Present.abi.json';

const client = createPublicClient({ chain: arbitrumSepolia, transport: http(process.env.RPC_URL) });
const PRESENT = '0x8cED4381845b1fB450C8D2279ed4c888A38fC08d';

// 合约现在只有一套统一的事件
client.watchContractEvent({ address: PRESENT, abi: presentAbi, eventName: 'WrapPresent', onLogs: logs => {/* logs[i].args.presentId */} });
client.watchContractEvent({ address: PRESENT, abi: presentAbi, eventName: 'UnwrapPresent', onLogs: logs => {} });
client.watchContractEvent({ address: PRESENT, abi: presentAbi, eventName: 'TakeBack', onLogs: logs => {} });
```
**读取礼物详情**
```ts
import { getContract } from 'viem';
const present = getContract({ address: PRESENT, abi: presentAbi, client });

// getPresent 返回核心状态信息
const [
    sender,
    title,
    description,
    status,
    expiryAt,
    distType,      // 分配模式 (enum)
    claimLimit,    // 领取上限
    claimedCount   // 已领取数量
] = await present.read.getPresent([presentId]);

// 使用辅助函数获取其它信息
const content = await present.read.getPresentContent([presentId]); // 获取资产列表
const recipients = await present.read.getPresentRecipients([presentId]); // 获取接收人/白名单
const prizeTiers = await present.read.getPresentPrizeTiers([presentId]); // 获取随机模式的奖池
```
要点：
- `presentId` 从事件 args 获取；`tokenId = uint256(presentId)`（两个 NFT 的 tokenId 对应同一礼物）
- `getPresent` 接口已更新，专注于返回状态。资产、接收人等列表信息通过独立的只读函数获取。

---

## 常见问题
- **如何创建不同类型的礼物？**
  - 所有类型的礼物都通过唯一的 `wrapPresent` 函数创建。您需要根据想创建的模式，正确地设置 `_distType`、`_recipients`、`_claimLimit` 和 `_prizeTiers` 这几个关键参数。
- **为什么要先 `approve` 再 wrap ERC20？**
  - 因为合约会调用 `transferFrom` 把代币从你地址托管到合约，需要你先授权额度。
- **要不要把“日志文件”发给前端？**
  - 不需要。miniapp/farcaster 直接从链上按 `PRESENT_ADDRESS` 订阅/拉取；`broadcast/` 仅供本地对照。

---

## 变更历史

### 接口统一化重构
- **接口变更**：
  - 所有 `wrap` 功能统一到唯一的 `wrapPresent` 函数中，该函数包含所有参数（元数据、分配模式等）。
  - 移除了所有 `...Test` 相关的冗余函数和事件，使接口和事件更加清晰。
- **脚本与测试更新**：所有脚本和测试文件都已更新，以适配新的统一接口。

### 功能升级：多种分配模式
- **新功能**：合约新增“限量均分”、“白名单均分”、“随机红包”三种分配模式。
- **接口变更**：
  - 新增 `wrapPresentWithOptions` 和 `wrapPresentRandom` 以支持新模式。
  - `unwrapPresent` 重构为 `claimPresent`，以处理不同模式下的领取逻辑。
  - `getPresent` 接口返回字段更新，并新增 `getPresentContent` 等辅助读函数。
- **脚本更新**：`GenerateSamples` 等脚本已更新，会生成覆盖所有新模式的样例数据。

### 初始版本
- 整理 ABI 目录：`abi/raw`（纯 ABI）、`abi/table`（可读表）。
- 新增脚本：`GenerateSamplesOnExisting.s.sol`、`WrapOnly.s.sol`、`WrapWithERC20.s.sol`。
- 补充测试网样例生成与 miniapp/farcaster 接入说明。
