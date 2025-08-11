# Handover for @contract-binj – Wrapped/Unwrapped Present ERC721

本文面向 @contract-binj，描述如何实现两个 ERC721：`WrappedPresentNFT` 与 `UnwrappedPresentNFT`，并与 `Present.sol` 平滑对接，满足 miniapp 与日志索引的使用需求。

## 背景与角色
- `Present.sol`（已完成，Solidity ^0.8.20）：
  - 打包/拆包/收回礼物，产生日志 `WrapPresent/UnwrapPresent/TakeBack`；
  - 提供 `contentOf`（public）与 `getPresentContent(bytes32)` 等接口；
  - 在 `wrapPresent` 成功后、`unwrapPresent` 成功后，分别调用对应 NFT 的 `mint`。
- 你负责：
  - 两个 ERC721：`WrappedPresentNFT`（打包后给 sender）、`UnwrappedPresentNFT`（拆包后给 taker）。
  - 元数据包含图片（建议 SVG on-chain 或 IPFS）与文字描述（礼物内容摘要）。
  - 仅允许 `Present` 合约调用 `mint`。

## 对接接口（强制）
- 需求文档建议暴露：`mint(bytes32 presentId)`，仅 `Present` 调用。当前 `Present.sol` 使用了：
  ```solidity
  interface IPresentNFT {
      function mint(address to, bytes32 presentId) external returns (uint256);
  }
  ```
- 为兼容两种说法，建议在 NFT 合约中：
  - 实现主接口：`mint(bytes32 presentId) external onlyPresent returns (uint256)`（由合约内部推导接收者）；
  - 同时提供重载：`mint(address to, bytes32 presentId) external onlyPresent returns (uint256)`（与当前 `Present.sol` 完全兼容）。
- 由 `onlyPresent` 修饰器约束调用方为 `Present` 合约地址（通过 `setPresentContract(address)` 设定）。

## 接收者确定逻辑
- Wrapped：接收者应为 wrap 的 `sender`（`Present` 内部为 `msg.sender`），你可在 `mint(bytes32)` 中通过 `Present` 读取 `senderOf[presentId]`；或在 `mint(address to, bytes32)` 中直接使用 `to`。
- Unwrapped：接收者为拆包的 `taker`（`unwrapPresent` 的调用者），同理可由 `Present` 传 `to`，或在 `mint(bytes32)` 从事件上下文读取不现实，因此建议 `Present` 传 `to`。

## 需要读取的 `Present` 数据
- `getPresentContent(bytes32)`：礼物资产明细 `Asset[] (address tokens, uint256 amounts)`。
- 公开 `contentOf[presentId]`、`senderOf[presentId]`、`recipientsOf[presentId]` 可直接 `presentContract.senderOf(presentId)` 等（均为 public getter）。
- `getPresentStatus(bytes32)`：状态（0 活跃/1 已拆/2 已收回/3 已过期）。

## TokenID/去重策略
- 建议 1:1 对应：`tokenId = uint256(presentId)`（把 `bytes32` 解释为 `uint256`）。
- 必须防重复铸造：维护 `mapping(bytes32 => bool) minted`；若已铸造则 revert。
- 两份 NFT 各自独立维护自己的 `minted` 映射。

## 访问控制与所有权
- 继承 `Ownable`（OZ）。
- `setPresentContract(address)`：仅 owner 可调；设置/更新 `Present` 合约地址。
- `onlyPresent` 修饰器用于 `mint`。

## 元数据（tokenURI）与图片
- 要求：图片与文字描述齐全；描述包含礼物内容摘要。
- 建议两种实现：
  1) On-chain SVG + JSON（Base64）：无需外部依赖，便于测试链与演示；
  2) Off-chain/IPFS：提供 `baseURI` 与 `tokenURI` 拼接；但需额外上传与运维。
- 建议默认采用 on-chain：
  - JSON fields：`name`、`description`、`image`（data:image/svg+xml;base64,…）、`attributes`（assets 列表概览、sender、recipientsCount、status）。
  - 注意 `attributes` 长度受 `maxAssetCount` 限制（Present 有上限），生成时控制 gas 与字符串长度；必要时只展示前 N 条与 totals 统计。

### 辅助工具
- Base64：`import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";`
- Hex utils：可将 `presentId` 以 0x…hex 展示；或显示截断。

## 合约骨架示例（要点）
```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

interface IPresentMinimal {
    struct Asset { address tokens; uint256 amounts; }
    function getPresentContent(bytes32 presentId) external view returns (Asset[] memory);
    function senderOf(bytes32 presentId) external view returns (address);
    function getPresentStatus(bytes32 presentId) external view returns (uint8);
}

abstract contract PresentNFTBase is ERC721, Ownable {
    address public presentContract;
    mapping(bytes32 => bool) internal minted;

    modifier onlyPresent() {
        require(msg.sender == presentContract, "Only Present");
        _;
    }
    function setPresentContract(address present) external onlyOwner { presentContract = present; }

    function _tokenId(bytes32 presentId) internal pure returns (uint256) {
        return uint256(presentId);
    }

    // 兼容两种签名
    function mint(bytes32 presentId) external virtual onlyPresent returns (uint256);
    function mint(address to, bytes32 presentId) external virtual onlyPresent returns (uint256);
}

contract WrappedPresentNFT is PresentNFTBase {
    constructor() ERC721("Wrapped Present", "WRAP") {}

    function mint(bytes32 presentId) external override onlyPresent returns (uint256 tokenId) {
        require(!minted[presentId], "Minted");
        address to = IPresentMinimal(presentContract).senderOf(presentId);
        tokenId = _tokenId(presentId);
        minted[presentId] = true;
        _safeMint(to, tokenId);
    }

    function mint(address to, bytes32 presentId) external override onlyPresent returns (uint256 tokenId) {
        require(!minted[presentId], "Minted");
        tokenId = _tokenId(presentId);
        minted[presentId] = true;
        _safeMint(to, tokenId);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        // 读取 present 数据并生成 Base64 JSON + SVG（略）
        // 返回 data:application/json;base64,…
    }
}

contract UnwrappedPresentNFT is PresentNFTBase {
    constructor() ERC721("Unwrapped Present", "UNWRAP") {}

    function mint(bytes32 presentId) external override onlyPresent returns (uint256 tokenId) {
        // 建议仅支持 mint(address,to) 由 Present 传入接收者；
        revert("Use mint(address,bytes32)");
    }

    function mint(address to, bytes32 presentId) external override onlyPresent returns (uint256 tokenId) {
        require(!minted[presentId], "Minted");
        tokenId = _tokenId(presentId);
        minted[presentId] = true;
        _safeMint(to, tokenId);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        // 同上，生成拆包后的描述
    }
}
```

> 说明：上述仅为骨架，`tokenURI` 内请根据 `getPresentContent` 读取资产并组装元数据，注意 gas 与字符串拼接成本。

## 与 Present 对接流程
1) 部署两个 NFT 合约；
2) 由 `Present` owner 调用：
   ```bash
   cast send $PRESENT_ADDRESS "setNFTContracts(address,address)" <wrapped> <unwrapped> \
     --rpc-url <RPC> --private-key <OWNER_PK>
   ```
3) `Present` 在 `wrapPresent`/`unwrapPresent` 时会分别调用 `wrappedNFT.mint(...)` 与 `unwrappedNFT.mint(...)`。

## 测试要求（Foundry）
- 新增 `test/`：
  - `WrappedPresentNFT.t.sol`、`UnwrappedPresentNFT.t.sol`：
    - onlyPresent 访问控制；
    - 重复 mint 拒绝；
    - tokenId=uint256(presentId)；
    - tokenURI 生成包含关键字段；
  - 集成测试：与 `Present` 联动，设置 NFT 合约地址后，走一次 wrap/unwrap，断言：
    - 事件正确；
    - NFT 分别铸给 sender / taker；
    - `getPresentContent` 与展示一致。
- 运行：
  ```bash
  forge test -vvv
  ```
- 本地 fork（零成本）端到端：按仓库 README 的“本地 fork 仿真”步骤，部署 Present → 设置 NFT → 调用 wrap/unwrap → 观察日志与 NFT 状态。

## 安全与边界
- onlyPresent 强约束；`setPresentContract` 仅 owner；
- 防重复 mint；
- tokenURI 读取 Present 时避免重入（view 调用），不要在 tokenURI 内做外部可变状态调用；
- 大数组处理：只展示前 N 条资产 + 汇总，防止过长字符串；
- 兼容性：提供 `mint(bytes32)` 与 `mint(address,bytes32)`，以适配当前 `Present` 行为与需求文档。

## 交付清单
- 合约：`WrappedPresentNFT.sol`、`UnwrappedPresentNFT.sol`（Solidity ^0.8.20，OZ ERC721 + Ownable）；
- 测试：上述单元与集成测试；
- 文档：简单 README（如何部署、`setPresentContract`、`setNFTContracts` 对接、`tokenURI` 说明与示例）。

如需变更 `mint` 接口签名或 `tokenURI` 元数据结构，请提前在群里沟通后再调整。 