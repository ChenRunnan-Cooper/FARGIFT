# FarGift 🎁

FarGift是一个基于Farcaster生态的礼物平台智能合约系统。该系统允许用户将ETH、ERC20代币打包成礼物，指定特定接收者或以红包形式发送给任何人。

## 特性

- 打包ETH、ERC20代币为礼物
- 支持指定接收者或公开红包模式
- 礼物NFT铸造（包装和拆开状态）
- 礼物过期和收回机制
- 安全特性：重入保护、防黑名单代币、紧急暂停等
- 完整的礼物生命周期管理

## 项目结构

- `src/Present.sol` - 核心礼物合约，负责资产托管与生命周期管理
- `src/nft/WrappedPresentNFT.sol` - 包装态礼物 NFT（`tokenId = uint256(presentId)`，从 `Present.getPresent` 读取元信息，on-chain SVG/JSON）
- `src/nft/UnwrappedPresentNFT.sol` - 拆包态礼物 NFT（同上）
- `test/` - `Present` 合约的单元测试与模拟合约
- `script/` - 部署与交互脚本（含仿真脚本）
- `deploy_when_funded.sh` - 余额监控自动部署脚本
- `foundry.toml` - Foundry 配置（remappings、rpc_endpoints、etherscan）
- `.env` - 环境变量（已在 `.gitignore` 中忽略）
- `env.example` - 环境变量模板（不含敏感信息）
- `HANDOVER_contract-binj.md` - 交接文档（NFT合约对接说明，供 @contract-binj 使用）
- `HANDOVER_miniapp.md` - 交接文档（日志索引与只读查询集成，供 MiniAPP 组使用）

### 项目目录树与文件用途

```
FarGift/
├── foundry.toml              # Foundry 配置：库路径、RPC端点、Etherscan API Key 等
├── .gitignore                # 忽略 .env、编译产物与本地dry-run等
├── .gitmodules               # 子模块（OpenZeppelin、forge-std）
├── README.md                 # 项目说明（部署、测试、目录与说明）
├── contract.md               # 需求与接口草案（事件、方法说明）
├── contract-new.md           # 新版需求（含 title/desc、建议聚合到 struct）
├── env.example               # .env 模板（不含敏感信息）
├── HANDOVER_contract-binj.md # 交接文档（ERC721 Wrapped/Unwrapped 对接与实现指南）
├── HANDOVER_miniapp.md       # 交接文档（MiniAPP 日志索引、WebSocket订阅、只读查询）
├── src/
│   ├── Present.sol           # 核心合约（礼物生命周期、权限、暂停、黑名单、紧急提取等）
│   └── nft/
│       ├── WrappedPresentNFT.sol   # 包装态礼物NFT
│       └── UnwrappedPresentNFT.sol # 拆包态礼物NFT
├── script/
│   ├── DeployPresent.s.sol   # 部署 Present
│   ├── DeployNFTs.s.sol      # 部署并对接两个 NFT 到 Present
│   ├── WrapOnceTest.s.sol    # 调用 wrapPresentTest 产生日志与 Wrapped NFT
│   ├── WrapPublicOnce.s.sol  # 公开领取示例的 wrapPresentTest 调用
│   └── SimulatePresent.s.sol # 一次性在仿真环境中完成部署+wrapPresent（fork或本地）
├── test/
│   ├── Present.t.sol         # Present 合约单测（37项）
│   └── mocks/
│       ├── MockERC20.sol     # 测试用ERC20
│       └── MockPresentNFT.sol# 测试用NFT，模拟wrapped/unwrapped NFT
├── deploy_when_funded.sh     # 监控余额达到阈值后自动部署并尝试验证
└── lib/                      # 外部依赖（OpenZeppelin、forge-std等）
```

## 安装

本项目使用[Foundry](https://book.getfoundry.sh/)构建。请先安装Foundry:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

然后克隆并设置项目:

```bash
git clone https://github.com/username/FarGift.git
cd FarGift
forge install
```

## 测试

运行所有测试:

```bash
forge test
```

查看测试覆盖率:

```bash
forge coverage
```

### 本次测试执行摘要

```text
Ran 37 tests for test/Present.t.sol:PresentTest → 全部通过
合计：37 通过，0 失败，0 跳过
```

### 单元测试明细（共37项：全部为 Present）

- 打包/基本功能（4）：
  - `test_WrapETHPresent`、`test_WrapTokenPresent`、`test_WrapMixedPresent`、`test_WrapPresent_NoNFTContract`
- 接收者与权限（6）：
  - `test_AnyoneCanUnwrap`、`test_UnwrapPresent`、`test_UnwrapPresent_Unauthorized`、`test_UnwrapPresent_AlreadyUnwrapped`、`test_TakeBack`、`test_TakeBack_Unauthorized`
- 收回边界（2）：
  - `test_TakeBack_AlreadyUnwrapped`、`test_TakeBack_AlreadyTakenBack`
- 过期机制（5）：
  - `test_PresentExpiry`、`test_ForceExpirePresent`、`test_ForceExpirePresent_Unauthorized`、`test_ForceExpirePresent_NonExistent`、`test_ForceExpirePresent_AlreadyUnwrapped`
- 暂停机制（3）：
  - `test_Pause`、`test_Pause_Unauthorized`、`test_Unpause_Unauthorized`
- 黑名单机制（3）：
  - `test_TokenBlacklist`、`test_CannotBlacklistETH`、`test_TokenBlacklist_Unauthorized`
- 紧急提取与安全（4）：
  - `test_EmergencyWithdraw`、`test_EmergencyWithdraw_Token`、`test_EmergencyWithdraw_Unauthorized`、`test_EmergencyWithdraw_InsufficientBalance`
- 配置（2）：
  - `test_UpdateConfig`、`test_UpdateConfig_Unauthorized`
- 容量上限（2）：
  - `test_TooManyAssets`、`test_TooManyRecipients`
- 金额与余额边界（3）：
  - `test_InsufficientETH`、`test_ETHRefund`、`test_ZeroAmount`
- 接口与集成（3）：
  - `test_OnERC721Received`、`test_SetNFTContracts`、`test_SetNFTContracts_Unauthorized`

当前结果：上述 37/37 全部通过（见“构建与测试”结果）。

## 部署

### 本地测试网

```bash
anvil  # 启动本地测试节点
forge script script/DeployPresent.s.sol:DeployPresent --rpc-url http://localhost:8545 --broadcast
```

### Arbitrum Sepolia测试网

设置环境变量:

```bash
export ARBITRUM_SEPOLIA_RPC_URL="https://sepolia-rollup.arbitrum.io/rpc"
export PRIVATE_KEY="your_private_key"
```

部署合约:

```bash
forge script script/DeployPresent.s.sol:DeployPresent --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast --verify
```

### 在已部署合约上执行测试调用

```bash
export PRESENT_ADDRESS="deployed_contract_address"
forge script script/DeployPresent.s.sol:TestPresentCalls --rpc-url $ARBITRUM_SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

## 合约功能

### 1. `wrapPresent` / `wrapPresentTest`

打包礼物，支持ETH和ERC20代币（未来将支持ERC721）。测试阶段建议使用带后缀的 `wrapPresentTest(recipients, title, desc, content)`，避免暴露正式 selector。

```solidity
function wrapPresent(address[] calldata recipients, Asset[] calldata content) external payable
function wrapPresentTest(address[] calldata recipients, string calldata title, string calldata desc, Asset[] calldata content) external payable
```

### 2. `unwrapPresent` / `unwrapPresentTest`

拆开礼物，仅允许指定接收者或在公开模式下任何人操作（空数组表示公开）。

```solidity
function unwrapPresent(bytes32 presentId) external
function unwrapPresentTest(bytes32 presentId) external
```

### 3. `takeBack` / `takeBackTest`

允许发送者收回未被拆开的礼物或已过期礼物。

```solidity
function takeBack(bytes32 presentId) external
function takeBackTest(bytes32 presentId) external
```

### 4. 只读聚合 `getPresent`

返回 sender、recipients、content、title、description、status、expiryAt，供 NFT/前端读取元信息。

```solidity
function getPresent(bytes32 presentId) external view returns (
  address sender,
  address[] memory recipients,
  Asset[] memory content,
  string memory title,
  string memory description,
  uint8 status,
  uint256 expiryAt
)
```

## 与前端集成

前端可以通过以下方式与合约交互:

1. 监听事件获取礼物ID（测试环境下推荐监听 `WrapPresentTest`）：
```javascript
const filter = presentContract.filters.WrapPresentTest();
const events = await presentContract.queryFilter(filter);
```

2. 查询礼物内容/元数据：
```javascript
const [sender, recipients, content, title, desc, status, expiryAt] = await presentContract.getPresent(presentId);
```

3. 若需要仅内容/状态：
```javascript
const content = await presentContract.getPresentContent(presentId);
const status = await presentContract.getPresentStatus(presentId);
```

## NFT 集成与一体化验证（本地 fork）

以下步骤在本地 anvil fork 上完成，不消耗真实 ETH：

1) 启动本地 fork 并注资部署地址：
```bash
anvil --fork-url https://arb-sepolia.g.alchemy.com/v2/<YOUR_KEY> --chain-id 421614 --port 8547
source .env
ADDR=$(cast wallet address --private-key "$PRIVATE_KEY")
cast rpc anvil_setBalance $ADDR 0xDE0B6B3A7640000 --rpc-url http://127.0.0.1:8547
```

2) 部署 Present：
```bash
forge script script/DeployPresent.s.sol:DeployPresent \
  --rpc-url http://127.0.0.1:8547 \
  --private-key "$PRIVATE_KEY" \
  --broadcast -vvv
export PRESENT_ADDRESS=<上一步输出的合约地址>
```

3) 部署并对接两个 NFT：
```bash
forge script script/DeployNFTs.s.sol:DeployNFTs \
  --rpc-url http://127.0.0.1:8547 \
  --private-key "$PRIVATE_KEY" \
  --broadcast -vvv
# 日志将打印 Wrapped 与 Unwrapped NFT 地址，已自动 set 到 Present
```

4) 执行一次 wrap（测试版接口）：
```bash
forge script script/WrapOnceTest.s.sol:WrapOnceTest \
  --rpc-url http://127.0.0.1:8547 \
  --private-key "$PRIVATE_KEY" \
  --broadcast -vvv
```

5) 从交易回执读取 presentId 与 tokenId（Wrapped 的 Transfer.topic[3]）：
```bash
TX=<上一步输出的交易哈希>
cast receipt $TX --rpc-url http://127.0.0.1:8547
# 日志中：
#  - Wrapped NFT 的 Transfer topics[3] = tokenId = presentId（同值）
#  - Present 的 WrapPresentTest topics[1] = presentId
```

6) 读取 Wrapped NFT 的 tokenURI（应返回 data:application/json;base64,...）：
```bash
WRAPPED=<Wrapped NFT 地址>
TOKENID=<上一步解析的 tokenId>
cast call --rpc-url http://127.0.0.1:8547 $WRAPPED "tokenURI(uint256)" $TOKENID
```

## 开发团队

- @Ranen(润楠) - Present.sol合约开发
- @contract-binj - ERC721 NFT合约开发

## 许可证

MIT

---

## 文件说明（详细）

- `src/Present.sol`
  - 核心合约，负责礼物的打包、拆包、收回、过期等全生命周期管理。
  - 关键事件：`WrapPresent/UnwrapPresent/TakeBack` 与测试期事件 `WrapPresentTest/UnwrapPresentTest/TakeBackTest`。
  - 关键结构：`struct PresentInfo { sender, recipients, content, title, description, status, createdAt, expiryAt }`；集中存储于 `mapping(bytes32 => PresentInfo) presents`。
  - 兼容性：为兼容旧测试与脚本，仍保留若干旧映射（如 `contentOf` 等）；推荐在正式版移除，仅保留 `presents`。
  - 只读：新增聚合只读 `getPresent(bytes32)` 便于前端/NFT 读取完整元信息。

- `script/DeployPresent.s.sol`
  - `DeployPresent`：读取 `PRIVATE_KEY`，部署 `Present`，输出合约地址。

- `script/DeployNFTs.s.sol`
  - 部署 `WrappedPresentNFT/UnwrappedPresentNFT`，调用 `setPresentContract`，并回填到 `Present.setNFTContracts`。

- `script/WrapOnceTest.s.sol`
  - 调用 `wrapPresentTest(recipients, title, desc, content)`，产生日志并铸造 Wrapped NFT。

- `test/Present.t.sol` 及相关 mocks
  - 覆盖礼物生命周期的核心路径（打包、拆包、收回、过期、黑名单、暂停等）。
  - 当前结果：全部通过（见上文“测试与验证记录”）。

- 其余文件说明保持不变。

## 运行脚本与常见输出/错误说明

### deploy_when_funded.sh 的输出为何一直打印余额为 0？
- 该脚本每隔一段时间（默认20±抖动秒）调用 `cast balance` 查询部署地址余额。
- 使用公共 RPC（`https://sepolia-rollup.arbitrum.io/rpc`）时，常见现象：
  - 长时间为 0：确实无入金或RPC短暂不可用；
  - 间歇性报错：
    - `tls handshake eof`、`client error (Connect)` 表示公共节点连接不稳定或被限流。

### 已做的修复与增强
- 脚本已支持多RPC回退与容错：
  - 新增环境变量 `ARBITRUM_SEPOLIA_RPC_URLS`（空格或逗号分隔多个RPC）。脚本会轮询可用RPC，优先使用可访问的一个；
  - 抑制 `cast balance` 的错误噪声并自动重试；
  - 增加抖动（jitter）与可配置轮询间隔（`POLL_INTERVAL`）。

### 如何配置更稳的RPC
- `.env` 中可配置：
```
# 单个主RPC（仍保留）
ARBITRUM_SEPOLIA_RPC_URL="https://sepolia-rollup.arbitrum.io/rpc"

# 多RPC回退（新增，可选；空格或逗号分隔）
ARBITRUM_SEPOLIA_RPC_URLS="https://arb-sepolia.g.alchemy.com/v2/<KEY> https://sepolia-rollup.arbitrum.io/rpc,https://arbitrum-sepolia.infura.io/v3/<KEY>"

# 可选：轮询间隔与阈值
POLL_INTERVAL=20
THRESH_WEI=2000000000000000
```
- 建议：使用 Alchemy/Infura 的专属 RPC（更稳定），并放在 `ARBITRUM_SEPOLIA_RPC_URLS` 的最前面。

### FAQ：常见坑与原因
- 一直显示 0 且伴随 `tls handshake eof`：
  - 原因：公共RPC不稳定/限流。本脚本现在会自动回退，但如果仅配置了单一公共RPC，仍可能频繁失败。
  - 解决：配置 `ARBITRUM_SEPOLIA_RPC_URLS`，加入 Alchemy/Infura 节点；或临时提升 `POLL_INTERVAL` 减少请求频率。
- `vm.envUint("PRIVATE_KEY") missing 0x`：
  - 原因：`.env` 的私钥缺少 `0x` 前缀。
  - 解决：确保 `PRIVATE_KEY="0x<64位hex>"`。
- 模拟执行正常、真实部署失败：
  - 原因：余额不足、RPC限流或 `ARBISCAN_API_KEY` 未配置。
  - 解决：确保余额≥阈值、换更稳RPC、配置API Key或先去掉 `--verify`。

## 安全性分析（更新）

- 访问控制与外部调用
  - `wrap/unwrap/takeBack` 全部 `nonReentrant`；`onlyRecipient` 对空接收者数组解释为公开；`onlySender` 用于收回；
  - NFT 铸造仅允许 `onlyPresent` 调用，`tokenId = uint256(presentId)` 防重复。
- 资金安全
  - ERC20 使用 `SafeERC20`；ETH 使用 `call` 并检查返回值；紧急提取 `onlyOwner`；黑名单可阻断已知问题代币；
  - Checks-Effects-Interactions 顺序：先更新状态与计数，再转资产。
- 过期与回收
  - `expiryAt` 控制过期；`canUnwrap` 先检查过期并 `PresentExpired`，再校验可拆包状态；回收仅在未拆包或过期时允许。
- 事件与索引
  - 生产与测试事件并存，测试部署建议使用 `*Test` 版本，防止过早暴露正式 selector；`presentId` 为 indexed 便于索引。
- 攻击面与缓解
  - 重入：`nonReentrant` + 状态先行；
  - Return bomb：`SafeERC20` 适配非标准 ERC20；
  - Gas DoS：`maxAssetCount/maxRecipientCount` 限制；
  - 重放与碰撞：`generatePresentId` 引入 `msg.sender/recipients/content/timestamp/prevrandao/address(this)`。

## 附录：公共测试网充值（可选，可能受限流/门槛）

### 方式一：测试水龙头（直接领）
- Alchemy 水龙头（Arbitrum Sepolia）：`https://www.alchemy.com/faucets/arbitrum-sepolia`
  - 连接 MetaMask（网络选择 Arbitrum Sepolia），输入部署地址领取
- QuickNode 水龙头：`https://faucet.quicknode.com/arbitrum/sepolia`
  - 连接钱包并完成验证，即可领取

提示：水龙头额度有限，可能需要间隔一段时间或更换不同水龙头。

### 方式二：从以太坊 Sepolia 桥接
- 原因：有些水龙头额度不足时，可先在以太坊 Sepolia 获得测试 ETH，再桥到 Arbitrum Sepolia
- 步骤：
  1) 以太坊 Sepolia 领水：
     - Alchemy：`https://www.alchemy.com/faucets/ethereum-sepolia`
     - Google faucet：`https://faucet.quicknode.com/ethereum/sepolia`
  2) 桥接到 Arbitrum Sepolia：
     - 官方桥：`https://bridge.arbitrum.io/`（网络选择 Sepolia→Arbitrum Sepolia）

### 如何确认到账
- 脚本日志会显示当前余额；或使用：
```bash
cast balance --rpc-url "$ARBITRUM_SEPOLIA_RPC_URL" 0x<你的地址>
```

## API Key 与测试钱包

### Arbiscan API Key（用于源码验证）
- 申请：
  1) 访问 `https://arbiscan.io/` → 注册/登录
  2) 用户中心 → API Keys → 新建 Key
  3) 把 Key 配置到 `.env` 的 `ARBISCAN_API_KEY`

### RPC 服务商 API Key（可选，但推荐，提升稳定性）
- Alchemy：
  - `https://www.alchemy.com/` → Create App → 选择 Arbitrum Sepolia → 复制 HTTPS URL
- Infura：
  - `https://www.infura.io/` → Create New Key → 选择 Web3 API → 网络选择 Arbitrum Sepolia → 复制 Endpoint
- 将这些 URL 放入 `.env` 的 `ARBITRUM_SEPOLIA_RPC_URLS`，置于最前以优先使用

### 测试钱包说明
- 强烈仅创建“测试专用钱包”用于测试网；不要复用主网钱包
- 导出私钥用于 `.env`（必须带 `0x`）：
  - MetaMask → 账户详情 → 导出私钥
- 不要把真实私钥/Key 提交到仓库；用于 README 的演示地址与私钥务必仅限测试/样例

## 覆盖率结果

- 本次覆盖率已生成 LCOV 报告：`lcov.info`
- 运行命令：
  ```bash
  forge coverage --report lcov
  ```
- 摘要（本地最新一次覆盖率执行节选）：
  ```text
  Ran 37 tests for test/Present.t.sol:PresentTest → 37/37 通过
  
  File                            | %Lines  | %Stmts | %Branches | %Funcs
  ------------------------------------------------------------------------
  src/Present.sol                 | 75.33%  | 75.00% | 66.67%    | 78.12%
  src/nft/WrappedPresentNFT.sol   | 0.00%   | 0.00%  | 0.00%     | 0.00%
  src/nft/UnwrappedPresentNFT.sol | 0.00%   | 0.00%  | 0.00%     | 0.00%
  Total                           | 44.31%  | 39.72% | 36.84%    | 51.90%
  ```
  - 说明：当前单测覆盖的是 `Present` 合约的核心业务路径；NFT 为显示层，未纳入单测覆盖统计（在本地 fork 端到端中验证）。如需提高总体覆盖率，可新增针对两个 NFT 的 `tokenURI`/`mint` 单测。

## env.example（模板）

- 仓库已提供 `env.example`（不含敏感信息）：
  - 复制为 `.env` 后填入自己的私钥与API Key
  - `ARBITRUM_SEPOLIA_RPC_URLS` 支持多个RPC（空格或逗号分隔）

```bash
cp env.example .env
# 然后编辑 .env 填入你的真实值
```

---

## 本地 fork 仿真（零成本）实测结果

本节记录“在不消耗任何真实 ETH”的前提下，于本地基于 Arbitrum Sepolia 的 fork 节点完成部署与一次 wrapPresent 的完整流程与结果。

### 环境
- 本地节点：
```bash
anvil --fork-url https://arb-sepolia.g.alchemy.com/v2/<YOUR_KEY> \
      --chain-id 421614 \
      --port 8547
```
- 部署地址：从 `.env` 的 `PRIVATE_KEY` 推导（示例）
```bash
source .env
cast wallet address --private-key "$PRIVATE_KEY"
# => 0x1840fCD5a8cC90F18d320477c691A038aa800B6B
```
- 本地注资（无需水龙头）：
```bash
cast rpc anvil_setBalance 0x1840fCD5a8cC90F18d320477c691A038aa800B6B 0xDE0B6B3A7640000 \
  --rpc-url http://127.0.0.1:8547
cast balance --rpc-url http://127.0.0.1:8547 0x1840fCD5a8cC90F18d320477c691A038aa800B6B
# => 1000000000000000000 (1 ETH)
```

### 部署与调用
- 部署 Present：
```bash
forge script script/DeployPresent.s.sol:DeployPresent \
  --rpc-url http://127.0.0.1:8547 \
  --private-key "$PRIVATE_KEY" \
  --broadcast -vvv
# 输出（示例）：
# Present contract deployed at: 0x...
```
- 调用 wrapPresent（或使用 `WrapOnceTest.s.sol`）：
```bash
export PRESENT_ADDRESS=0x<DeployPresent输出地址>
forge script script/WrapOnceTest.s.sol:WrapOnceTest \
  --rpc-url http://127.0.0.1:8547 \
  --private-key "$PRIVATE_KEY" \
  --broadcast -vvv
# 输出（示例）：wrapPresentTest executed
```

### 提取 presentId（从交易日志）
- 方式一：交易回执解析（推荐）
```bash
TX=0x<WrapOnceTest交易哈希>
cast receipt $TX --rpc-url http://127.0.0.1:8547
# 日志中：
#  - Wrapped NFT 的 Transfer topics[3] = tokenId = presentId
#  - Present 的 WrapPresentTest topics[1] = presentId
```
- 方式二：按区块范围检索合约 Logs
```bash
cast logs --from-block <BLOCK> --to-block <BLOCK> \
  --address $PRESENT_ADDRESS \
  --rpc-url http://127.0.0.1:8547 | grep -A2 WrapPresentTest
```

### 校验礼物内容（供前端/miniapp联调）
```bash
cast call $PRESENT_ADDRESS \
  "getPresent(bytes32)((address,address[],(address,uint256)[],string,string,uint8,uint256))" \
  0x<PRESENT_ID> \
  --rpc-url http://127.0.0.1:8547
```

### 常见坑（本地 fork 场景）
- 端口占用（os error 48）：已有进程占用 8545，改用 `--port 8547` 或杀掉占用进程：
```bash
lsof -nP -iTCP:8545 -sTCP:LISTEN
kill -9 <PID>
```
- `--fork-url` 变量未展开：不要把 `export` 和 `anvil` 写在同一行，更不要加管道；建议直接把 URL 写死在命令里。
- `lack of funds ... for max fee`：仅仿真时会预估费用校验；在本地 fork 场景下使用 `anvil_setBalance` 注资后再广播即可。
- `PRESENT_ADDRESS` 解析失败：确保为真实 0x 地址，不要使用占位符。

### 安全查看 .env（不泄露私钥）
```bash
awk -F= '/^ARBITRUM_SEPOLIA_RPC_URLS=|^ARBITRUM_SEPOLIA_RPC_URL=|^ARBISCAN_API_KEY=/{print} /^PRIVATE_KEY=/{print "PRIVATE_KEY=***redacted***"}' .env
source .env && cast wallet address --private-key "$PRIVATE_KEY"
```

## 测试结果分析

- 单元测试：Present 37/37 通过，覆盖核心业务路径（打包/拆包/收回/过期/暂停/黑名单/紧急提取/配置/边界等）。
- 覆盖率：已生成 `lcov.info`，可在本地或CI中展示，辅助评估改动对覆盖的影响。
- 零成本本地 fork（基于 Arbitrum Sepolia）实测：
  - 本地启动 anvil fork + 本地 `anvil_setBalance` 注资 + 本地真实广播（仅在本地），成功完成部署与一次 `wrapPresentTest` 调用；
  - 通过 `cast receipt` 从交易日志中解析 indexed `presentId`，并用 `getPresent`/`getPresentContent` 校验礼物元信息与内容；
  - 该路径不依赖任何水龙头或真实ETH，适合前端/miniapp联调与团队内部验收。
- 公共测试网（可选）：
  - 受限于部分水龙头的反女巫门槛及公共RPC限流/不稳定，短期内不作为主流程；
  - 推荐在具备稳定 RPC（Alchemy/Infura）与可用水龙头时再行尝试，或由同组同学转少量测试ETH；
  - 文档将此作为附录保留，供后续需要时参考。

### 本次一体化（含 NFT）本地 fork 演示记录

- 环境：anvil 本地 fork（Arbitrum Sepolia），本地注资 1 ETH
- 合约地址（本地 fork 实例）：
  - Present: `0x22F2800aeE94c9e57D76981bC13e7a3760D396D9`
  - WrappedPresentNFT: `0xFf1e6Ed2d485A5E10BB1bD28191a3Fba68CB9d72`
  - UnwrappedPresentNFT: `0x3F4FbC0E1296FA2742AD1319D66Ca91c8377a11A`
- wrap（指定接收者示例）：
  - 脚本：`script/WrapOnceTest.s.sol`
  - 交易哈希：`0xa58b2e0bea8abf9c3fb6826103d641a100adaea7adc6e549e0005f1ba856f5d9`
  - 日志要点：
    - Wrapped ERC721 Transfer 的 `topics[3]`（即 `tokenId`）= `0x70a18f80dd4ae3fb45451b72c56f4ca90773fe79ff8edcf9aff774c1ec5b6403`
    - Present 的 `WrapPresentTest` 的 `topics[1]`（`presentId`）与上面 `tokenId` 一致
  - tokenURI 调用（截断显示）：
    - `cast call <WrappedNFT> "tokenURI(uint256)" <tokenId>` 返回 `