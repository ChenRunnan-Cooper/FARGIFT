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
├── env.example               # .env 模板（不含敏感信息）
├── HANDOVER_contract-binj.md # 交接文档（ERC721 Wrapped/Unwrapped 对接与实现指南）
├── HANDOVER_miniapp.md       # 交接文档（MiniAPP 日志索引、WebSocket订阅、只读查询）
├── src/
│   └── Present.sol           # 核心合约（礼物生命周期、权限、暂停、黑名单、紧急提取等）
├── script/
│   ├── DeployPresent.s.sol   # 部署与交互脚本（DeployPresent、TestPresentCalls 等）
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

### 1. `wrapPresent`

打包礼物，支持ETH和ERC20代币（未来将支持ERC721）。

```solidity
function wrapPresent(address[] calldata recipients, Asset[] calldata content) external payable
```

### 2. `unwrapPresent`

拆开礼物，仅允许指定接收者或在公开模式下任何人操作。

```solidity
function unwrapPresent(bytes32 presentId) external
```

### 3. `takeBack`

允许发送者收回未被拆开的礼物或已过期礼物。

```solidity
function takeBack(bytes32 presentId) external
```

## 与前端集成

前端可以通过以下方式与合约交互:

1. 监听事件获取礼物ID:
```javascript
const filter = presentContract.filters.WrapPresent();
const events = await presentContract.queryFilter(filter);
```

2. 查询礼物内容:
```javascript
const content = await presentContract.getPresentContent(presentId);
```

3. 查询礼物状态:
```javascript
const status = await presentContract.getPresentStatus(presentId);
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
  - 关键事件：`WrapPresent`、`UnwrapPresent`、`TakeBack`（与最初接口保持一致）。
  - 关键结构：`Asset { address tokens; uint256 amounts; }`，同时内部扩展了 `ExtendedAsset` 以便将来兼容 NFT。
  - 关键状态：`mapping(bytes32 => Asset[]) contentOf` 保留了原接口；并扩展存储发送者、接收者、状态、过期时间、黑名单等。
  - 构造函数：`constructor(address initialOwner)`，部署脚本传入部署者地址为 owner。

- `script/DeployPresent.s.sol`
  - `DeployPresent`：读取环境变量 `PRIVATE_KEY`（以 `vm.envUint` 形式，要求16进制且带 `0x` 前缀），`vm.startBroadcast` 后部署 `Present`，输出合约地址。
  - `DeployPresentWithNFTs`：预留部署并设置 NFT 合约的流程（当前未启用）。
  - `TestPresentCalls`：示例交互脚本，读取 `PRIVATE_KEY` 和 `PRESENT_ADDRESS`，向 `wrapPresent` 发送 0.01 ETH 创建礼物（用于链上交互验证）。

- `test/Present.t.sol` 及相关 mocks
  - 覆盖礼物生命周期的核心路径（打包、拆包、收回、过期、黑名单、暂停等）。
  - 当前结果：全部通过（见上文“测试与验证记录”）。

- `deploy_when_funded.sh`
  - 新增的自动化部署脚本：轮询部署地址余额，超过阈值（默认 0.002 ETH）后自动执行部署并尝试验证。
  - 依赖 `.env` 中的变量：`ARBITRUM_SEPOLIA_RPC_URL`、`PRIVATE_KEY`（需 0x 前缀）、`ARBISCAN_API_KEY`。

- `foundry.toml`
  - `remappings` 指向 OpenZeppelin 合约库。
  - `[rpc_endpoints]` 配置了 `arbitrum_sepolia = "${ARBITRUM_SEPOLIA_RPC_URL}"`，便于命令引用。
  - `[etherscan]` 配置了 `arbitrum_sepolia` 的 API Key 占位（也可通过命令行 `--etherscan-api-key` 传入）。

- `.env`（被 `.gitignore` 忽略）
  - 示例字段：
    - `ARBITRUM_SEPOLIA_RPC_URL="https://sepolia-rollup.arbitrum.io/rpc"`
    - `PRIVATE_KEY="0x<64位十六进制>"`（重要：脚本用 `vm.envUint` 读取，必须带 `0x` 前缀）
    - `ARBISCAN_API_KEY="<你的Arbiscan API Key>"`

- `HANDOVER_contract-binj.md`
  - ERC721 Wrapped/Unwrapped 实现与对接 Present 的交接文档：接口、onlyPresent 权限、tokenURI 元数据方案、测试与联调流程。

- `HANDOVER_miniapp.md`
  - MiniAPP 端日志索引、getLogs 分段回放、WebSocket 实时订阅、只读查询 getPresentContent 的集成指南。

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

## 安全性分析（仅分析，未改动）

- 重入/双花相关：
  - 外部转账点位：
    - `wrapPresent` 末尾对多余 ETH 的退款（`call`），`wrapPresent` 本身不更新跨交易可争抢的余额计账，且后续无状态依赖；
    - `_transferAssets` 在 `unwrapPresent` 与 `takeBack` 中调用，均采用 Checks-Effects-Interactions：先更新 `presentStatus` 与统计，再转账（ETH使用 `call`，ERC20 使用 `safeTransfer`）。
  - 防护：合约继承 `ReentrancyGuard` 且对外部可转账路径均有 `nonReentrant` 修饰（`wrapPresent`/`unwrapPresent`/`takeBack`），重入窗口受限；状态先行更新，避免二次领取。
  - 结论：针对典型可重入-双花场景具备鲁棒性；仍需留意第三方代币的非标准行为（已用 `SafeERC20` 缓解）。

- Gas 消耗：
  - 可变长数组操作（资产/接收者）受上限约束：`maxAssetCount`、`maxRecipientCount`，避免极端大数组导致的 gas 爆炸与 DoS；
  - `wrapPresent` 的 `content` 写入 `storage`，和 `unwrap/takeBack` 的线性转账成本与资产数量线性相关，符合预期；
  - 内部循环仅对长度受限数组进行，当前实现对 gas 攻击具有一定鲁棒性。

- Return bomb（返回数据炸弹）：
  - 外部调用点为 `IERC20.safeTransfer` 与 `IERC20.safeTransferFrom`（通过 OpenZeppelin `SafeERC20` 封装）；该封装对无返回值、false返回、revert的情况均兼容处理，降低 ERC20 非标准返回数据导致的漏洞。
  - 读取函数 `getPresentContent` 返回内存数组（来自 `storage` 拷贝），可能在极端大礼物时 gas 偏高，但受 `maxAssetCount` 限制，不构成炸弹风险。

- 其他注意：
  - `generatePresentId` 使用 `msg.sender`、`recipients`、`content`、`timestamp`、`prevrandao`、`address(this)` 生成 ID，避免跨链/跨实例重放与碰撞；
  - `onlyRecipient` 对“任意人可领”通过空数组表示，逻辑清晰；
  - `emergencyWithdraw` 仅 owner 可用，并检查余额/使用 `SafeERC20`。

整体结论：当前代码在常见漏洞面具有较好防护；进一步增强可以考虑：
- 对 ERC20 实现 `safeIncreaseAllowance`/`safeDecreaseAllowance` 等路径的测试补充（非必须）；
- 对事件中补充更多上下文（非安全必需）。

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
- 摘要（测试输出节选）：
  - 37/37 测试通过；覆盖率详见 `lcov.info`（可用 VSCode 插件或 CI 展示）

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
  # 输出（节选）：
  # Present contract deployed at: 0x3B3cF7ee8dbCDDd8B8451e38269D982F351ca3db
  # Hash: 0x345083170b9f55f61e8b1970d7d2fdf7aff8f981dbf930db99fbfe738ad4b35c
  ```
- 调用 wrapPresent：
  ```bash
  export PRESENT_ADDRESS=0x3B3cF7ee8dbCDDd8B8451e38269D982F351ca3db
  forge script script/DeployPresent.s.sol:TestPresentCalls \
    --rpc-url http://127.0.0.1:8547 \
    --private-key "$PRIVATE_KEY" \
    --broadcast -vvv
  # 输出（节选）：
  # Gift created successfully
  # Hash: 0x053fb082366464a1f56388f1f643bbcc41a86bd4cd71e25eafff88b4c28ed32a
  ```

### 提取 presentId（从交易日志）
- 方式一：交易回执解析（推荐）
  ```bash
  TX=0x053fb082366464a1f56388f1f643bbcc41a86bd4cd71e25eafff88b4c28ed32a
  cast receipt $TX --rpc-url http://127.0.0.1:8547 | jq -r \
    '.logs[] | select(.topics[0]=="0xf57d75a06786ec46ba529c7c6a4a8c5f0c1eae07a3a01fa6c75da0320a9f7588") | .topics[1]'
  # 输出即为 presentId（bytes32）
  ```
- 方式二：按区块范围检索合约 Logs
  ```bash
  # 根据需要替换区块范围
  cast logs --from-block <BLOCK> --to-block <BLOCK> \
    --address $PRESENT_ADDRESS \
    --rpc-url http://127.0.0.1:8547 | grep -A2 WrapPresent
  ```

### 校验礼物内容（供前端/miniapp联调）
```bash
cast call $PRESENT_ADDRESS \
  "getPresentContent(bytes32)((address,uint256)[])" \
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
# 查看关键信息但不显示私钥
awk -F= '/^ARBITRUM_SEPOLIA_RPC_URLS=|^ARBITRUM_SEPOLIA_RPC_URL=|^ARBISCAN_API_KEY=/{print} /^PRIVATE_KEY=/{print "PRIVATE_KEY=***redacted***"}' .env
# 或仅验证地址推导是否正确
source .env && cast wallet address --private-key "$PRIVATE_KEY"
```

## 测试结果分析

- 单元测试：Present 37/37 通过，覆盖核心业务路径（打包/拆包/收回/过期/暂停/黑名单/紧急提取/配置/边界等）。
- 覆盖率：已生成 `lcov.info`，可在本地或CI中展示，辅助评估改动对覆盖的影响。
- 零成本本地 fork（基于 Arbitrum Sepolia）实测：
  - 本地启动 anvil fork + 本地 `anvil_setBalance` 注资 + 本地真实广播（仅在本地），成功完成部署与一次 `wrapPresent` 调用；
  - 通过 `cast receipt` 从交易日志中解析 `WrapPresent` 的 indexed `presentId`，并用 `getPresentContent` 校验礼物内容；
  - 该路径不依赖任何水龙头或真实ETH，适合前端/miniapp联调与团队内部验收。
- 公共测试网（可选）：
  - 受限于部分水龙头的反女巫门槛（如“需要主网0.001ETH”），以及公共RPC的限流/不稳定，短期内不作为主流程；
  - 推荐在具备稳定 RPC（Alchemy/Infura）与可用水龙头时再行尝试，或由同组同学转少量测试ETH；
  - 文档将此作为附录保留，供后续需要时参考。
