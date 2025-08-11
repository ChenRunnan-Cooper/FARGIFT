// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/*
================================================================================
合约整体说明（Present.sol）
--------------------------------------------------------------------------------
一、合约目标
- 该合约提供一个“链上送礼/收礼”系统：
  - 送礼人可以把 ETH 与 ERC20 代币打包成“礼物”（wrap），生成唯一礼物ID并托管在合约中；
  - 礼物可以指定接收人名单，或留空表示“任何人可拆”；
  - 接收人可以在有效期内拆开礼物（unwrap）并领取其中资产；
  - 送礼人在需要时可以收回礼物（takeBack），包括：仍处于激活状态的礼物或已过期礼物；
  - 合约在打包与拆包时分别可触发铸造两类 ERC721 凭证（Wrapped/Unwrapped），用于状态凭证与展示。

二、核心工作流程
- wrapPresent：
  1) 校验资产与接收人数量；黑名单代币校验；ETH 充足性校验；
  2) 生成唯一的 presentId，并确保未被使用；
  3) 对每个 ERC20 
     从 msg.sender 转入当前合约托管（需要发送者提前 approve）；
  4) 写入持久化存储（PresentInfo），设置状态与过期时间；
  5) 统计计数更新；
  6) 若配置了 Wrapped NFT 合约，则为发送者铸造“已打包”凭证；
  7) 触发事件；
  8) 退回多余的 ETH（如果 msg.value 超出需要的 ETH 总额）。

- unwrapPresent：
  1) 校验礼物存在、未过期、状态允许、调用者具备接收资格（或礼物公开）；
  2) 更新状态为 UNWRAPPED，统计计数；
  3) 将礼物中的 ETH/ERC20 逐项转给调用者；
  4) 若配置了 Unwrapped NFT 合约，则为调用者铸造“已拆包”凭证；
  5) 触发事件。

- takeBack：
  1) 仅送礼人可调用；
  2) 允许在礼物 ACTIVE 或已过期时收回；
  3) 更新状态为 TAKEN_BACK；
  4) 将礼物中的资产转回送礼人；
  5) 触发事件。

三、安全与运营设计
- 使用 OpenZeppelin 的 Ownable（管理员控制）、Pausable（全局暂停）、
  ReentrancyGuard（防重入）与 SafeERC20（安全代币转账）。
- 遵循 Checks-Effects-Interactions：先校验与写状态、再进行外部交互（转账/NFT 铸造）。
- 过期逻辑在校验时即时生效，避免边界竞态；
- 支持代币黑名单、紧急提取、强制过期等运营手段；
- 提供读接口（getPresent/getPresentContent/getPresentStatus）供前端/后端展示。

四、重要概念
- presentId：礼物唯一标识，基于（sender, recipients, content, timestamp, prevrandao, address(this)）
  进行 keccak256 生成，碰撞概率极低。
- recipients：接收人数组，长度为 0 表示“任何人可拆”。
- 状态机：0=ACTIVE, 1=UNWRAPPED, 2=TAKEN_BACK, 3=EXPIRED。

五、文件导航
- 事件：记录 Wrap/Unwrap/TakeBack/Expired/配置/黑名单等关键动作；
- 数据：PresentInfo、黑名单与统计；
- 入口：wrapPresent/unwrapPresent/takeBack；
- 管理：setNFTContracts/setTokenBlacklist/updateConfig/pause/unpause/
        emergencyWithdraw/forceExpirePresent；
- 工具：generatePresentId/_transferAssets/_getStatus/_isExpired 等。
================================================================================
*/

// 导入OpenZeppelin库（权限、暂停、防重入、ERC接口与安全转账工具）
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";                // 管理员控制
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";  // 防重入
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";                // 暂停/恢复
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";             // ERC20 接口
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; // 安全 ERC20 转账
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";          // ERC721 接口（预留）
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol"; // ERC721 接收接口

/**
 * @title Present
 * @dev 礼物包装、拆包和收回系统；支持 ETH 与 ERC20 托管，并通过 NFT 进行“状态凭证化”。
 * 功能：wrap（打包）/ unwrap（拆包）/ takeBack（收回）/ 过期检测与运营管理
 */
interface IPresentNFT {
    // 最小化 NFT 铸造接口；合约只依赖 mint 行为，不关心实现细节
    function mint(address to, bytes32 presentId) external returns (uint256);
}

// 合约主体：继承 Ownable/Pausable/ReentrancyGuard 并实现 IERC721Receiver（为将来支持 ERC721 做准备）
contract Present is Ownable, ReentrancyGuard, Pausable, IERC721Receiver {
    using SafeERC20 for IERC20; // 为 IERC20 增加 safeTransfer/safeTransferFrom 等扩展方法

    // -----------------------------
    // 事件（链上可观测性与索引）
    // -----------------------------
    event WrapPresent(bytes32 indexed presentId, address sender);           // 打包礼物
    event UnwrapPresent(bytes32 indexed presentId, address taker);          // 拆包礼物
    event TakeBack(bytes32 indexed presentId, address sender);              // 收回礼物
    event WrapPresentTest(bytes32 indexed presentId, address sender);       // 测试/演示环境下的打包事件
    event UnwrapPresentTest(bytes32 indexed presentId, address taker);      // 测试/演示环境下的拆包事件
    event TakeBackTest(bytes32 indexed presentId, address sender);          // 测试/演示环境下的收回事件
    event PresentExpired(bytes32 indexed presentId, address indexed sender); // 礼物过期事件（即时标记）
    event EmergencyWithdraw(address indexed token, address indexed to, uint256 amount); // 紧急提取
    event TokenBlacklisted(address indexed token, bool status);             // 代币黑名单变更
    event ConfigUpdated(string indexed paramName, uint256 oldValue, uint256 newValue); // 关键参数更新

    // -----------------------------
    // 数据结构
    // -----------------------------
    struct Asset {
        address tokens;   // 资产合约地址；address(0) 表示 ETH，其它为 ERC20 合约地址
        uint256 amounts;  // 数量；ETH 为 wei，ERC20 视代币精度
    }

    struct PresentInfo {
        bytes32 id;             // 礼物唯一 ID（哈希）
        address sender;         // 送礼人地址
        address[] recipients;   // 接收者列表；长度为 0 表示公开礼物（任何人可拆）
        Asset[] content;        // 资产明细（ETH/代币）
        string title;           // 标题（展示用）
        string description;     // 描述（展示用）
        uint8 status;           // 状态：0 active, 1 unwrapped, 2 takenBack, 3 expired
        uint256 createdAt;      // 创建时间戳
        uint256 expiryAt;       // 过期时间戳（createdAt + defaultExpiryPeriod）
    }

    // -----------------------------
    // 状态常量（状态机编码）
    // -----------------------------
    uint8 private constant PRESENT_ACTIVE = 0;      // 正常激活
    uint8 private constant PRESENT_UNWRAPPED = 1;   // 已拆包
    uint8 private constant PRESENT_TAKEN_BACK = 2;  // 已被寄件人收回
    uint8 private constant PRESENT_EXPIRED = 3;     // 已过期（逻辑映射）

    // -----------------------------
    // 配置参数（可由管理员更新）
    // -----------------------------
    uint256 public maxAssetCount = 20;              // 单个礼物最大资产条目数量
    uint256 public maxRecipientCount = 100;         // 单个礼物最大接收人数量
    uint256 public defaultExpiryPeriod = 365 days;  // 默认有效期（自创建起算）
    uint256 public minValueForGiftDisplay = 0;      // UI 展示门槛（目前未强制使用）

    // -----------------------------
    // 主存储与风控
    // -----------------------------
    mapping(bytes32 => PresentInfo) public presents;     // 礼物 ID → 礼物信息
    mapping(address => bool) public blacklistedTokens;    // 代币黑名单；true 表示禁止接收

    // -----------------------------
    // 统计信息（用于数据面板/激励/分析）
    // -----------------------------
    uint256 public totalPresentsWrapped;                 // 系统累计打包次数
    uint256 public totalPresentsUnwrapped;               // 系统累计拆包次数
    uint256 public totalPresentsTakenBack;               // 系统累计收回次数
    uint256 public totalPresentsExpired;                 // 系统累计过期次数（检测时即时累加）
    mapping(address => uint256) public userWrappedCount; // 每个地址的打包次数
    mapping(address => uint256) public userUnwrappedCount; // 每个地址的拆包次数

    // -----------------------------
    // 外部 NFT 合约地址（可由管理员设置）
    // -----------------------------
    address public wrappedNFT;    // 打包时铸造的凭证 NFT（可选）
    address public unwrappedNFT;  // 拆包时铸造的凭证 NFT（可选）

    // 构造函数：设置初始管理员（所有者）
    constructor(address initialOwner) Ownable(initialOwner) {}

    // ------------------------------------------------------------------------
    // 修饰符（权限与状态校验）
    // ------------------------------------------------------------------------

    // 校验礼物存在：如果 sender 为 0 地址，说明该 presentId 未被创建
    modifier presentExists(bytes32 presentId) {
        require(presents[presentId].sender != address(0), "Present does not exist");
        _; // 通过校验后继续执行函数主体
    }

    // 校验可拆包：若已过期，立即标记为 EXPIRED，统计 +1 并发出事件，然后回退；
    // 若未过期，则要求当前状态为 ACTIVE 才可继续
    modifier canUnwrap(bytes32 presentId) {
        if (_isExpired(presentId)) {
            _setStatus(presentId, PRESENT_EXPIRED);
            totalPresentsExpired++;
            emit PresentExpired(presentId, _getSender(presentId));
            revert("Present has expired");
        }
        uint8 status = _getStatus(presentId);
        require(status == PRESENT_ACTIVE, "Present cannot be unwrapped");
        _; // 继续执行后续代码
    }

    // 仅允许礼物发送者调用（如收回礼物）
    modifier onlySender(bytes32 presentId) {
        require(_getSender(presentId) == msg.sender, "Only sender can call this function");
        _;
    }

    // 仅允许接收者拆包；若 recipients 为空数组，表示任何人可拆
    modifier onlyRecipient(bytes32 presentId) {
        address[] memory recipients = _getRecipients(presentId);
        bool isRecipient = recipients.length == 0; // 公开礼物：任何人可拆
        if (!isRecipient) {
            for (uint i = 0; i < recipients.length; i++) {
                if (recipients[i] == msg.sender) { isRecipient = true; break; }
            }
        }
        require(isRecipient, "Only recipient can unwrap this present");
        _;
    }

    // 代币黑名单检查（当前逻辑在 _wrap 中以 require 方式实现；此修饰符预留复用）
    modifier tokenNotBlacklisted(address token) {
        if (token != address(0)) {
            require(!blacklistedTokens[token], "Token blacklisted");
        }
        _;
    }

    // ------------------------------------------------------------------------
    // 外部接口：打包礼物（不带标题/描述的简洁版本）
    // - payable：允许随交易附带 ETH；
    // - nonReentrant：防重入；
    // - whenNotPaused：合约暂停时不可调用
    // ------------------------------------------------------------------------
    function wrapPresent(address[] calldata recipients, Asset[] calldata content)
        external payable nonReentrant whenNotPaused
    {
        // 将入参映射到内部实现；标题/描述留空；emitTest=false 触发正式事件
        _wrap({recipients: recipients, title: "", description: "", content: content, emitTest: false});
    }

    // 外部接口：打包礼物（带标题/描述；用于测试或演示时触发 *_Test 事件）
    function wrapPresentTest(
        address[] calldata recipients,
        string calldata title,
        string calldata description,
        Asset[] calldata content
    ) external payable nonReentrant whenNotPaused {
        _wrap({recipients: recipients, title: title, description: description, content: content, emitTest: true});
    }

    // ------------------------------------------------------------------------
    // 内部实现：核心打包逻辑
    // 步骤：校验 → 计算所需 ETH → 生成 ID → 托管 ERC20 → 写存储 → 统计 → 铸 NFT → 事件 → 退款
    // 注意：遵循 Checks-Effects-Interactions，先写入状态再进行外部交互
    // ------------------------------------------------------------------------
    function _wrap(
        address[] calldata recipients,
        string memory title,
        string memory description,
        Asset[] calldata content,
        bool emitTest
    ) internal {
        // 1) 基本参数与风控校验
        require(content.length > 0 && content.length <= maxAssetCount, "Invalid content size");
        require(recipients.length <= maxRecipientCount, "Too many recipients");

        // 统计礼物中的 ETH 需求总额（address(0) 代表 ETH）
        uint256 ethValue = 0;
        for (uint i = 0; i < content.length; i++) {
            require(!blacklistedTokens[content[i].tokens], "Contains blacklisted token"); // 黑名单校验
            if (content[i].tokens == address(0)) { ethValue += content[i].amounts; }        // 累加 ETH 需求
            require(content[i].amounts > 0, "Amount must be positive");                    // 金额必须为正
        }
        require(msg.value >= ethValue, "Insufficient ETH sent"); // 确保随交易附带的 ETH 足够覆盖

        // 2) 生成唯一礼物 ID，并校验未被占用
        bytes32 presentId = generatePresentId(recipients, content);
        require(presents[presentId].sender == address(0), "Present ID exists");

        // 3) 托管 ERC20（需要发送者在调用前对本合约进行 approve）
        for (uint i = 0; i < content.length; i++) {
            if (content[i].tokens != address(0)) {
                IERC20(content[i].tokens).safeTransferFrom(msg.sender, address(this), content[i].amounts);
            }
        }

        // 4) 写入持久化存储（PresentInfo）
        PresentInfo storage p = presents[presentId];
        p.id = presentId;
        p.sender = msg.sender;
        p.recipients = recipients;   // calldata → storage 复制
        p.title = title;
        p.description = description;
        p.status = PRESENT_ACTIVE;
        p.createdAt = block.timestamp;
        p.expiryAt = block.timestamp + defaultExpiryPeriod;
        for (uint i2 = 0; i2 < content.length; i2++) { p.content.push(content[i2]); }

        // 5) 统计
        totalPresentsWrapped++;
        userWrappedCount[msg.sender]++;

        // 6) 可选：为发送者铸造“已打包”凭证 NFT（若已配置合约地址）
        if (wrappedNFT != address(0)) {
            IPresentNFT(wrappedNFT).mint(msg.sender, presentId);
        }

        // 7) 事件（测试或正式）
        if (emitTest) emit WrapPresentTest(presentId, msg.sender);
        else emit WrapPresent(presentId, msg.sender);

        // 8) 退回多余 ETH（若 msg.value 超过所需 ethValue）
        if (msg.value > ethValue) {
            (bool success, ) = msg.sender.call{value: msg.value - ethValue}("");
            require(success, "ETH refund failed");
        }
    }

    // ------------------------------------------------------------------------
    // 外部接口：拆包领取（必须：礼物存在、未过期、状态允许、具备接收资格）
    // 顺序：状态更新 → 统计 → 资产转移 → 可选铸 NFT → 事件
    // ------------------------------------------------------------------------
    function unwrapPresent(bytes32 presentId)
        external nonReentrant whenNotPaused presentExists(presentId) canUnwrap(presentId) onlyRecipient(presentId)
    {
        _setStatus(presentId, PRESENT_UNWRAPPED);     // 状态：已拆包
        totalPresentsUnwrapped++;                     // 系统统计
        userUnwrappedCount[msg.sender]++;             // 用户统计
        _transferAssets(presentId, msg.sender);       // 将礼物中的资产全部转给调用者
        if (unwrappedNFT != address(0)) { IPresentNFT(unwrappedNFT).mint(msg.sender, presentId); }
        emit UnwrapPresent(presentId, msg.sender);    // 事件
    }

    // 测试/演示版本（触发 *_Test 事件）
    function unwrapPresentTest(bytes32 presentId)
        external nonReentrant whenNotPaused presentExists(presentId) canUnwrap(presentId) onlyRecipient(presentId)
    {
        _setStatus(presentId, PRESENT_UNWRAPPED);
        totalPresentsUnwrapped++;
        userUnwrappedCount[msg.sender]++;
        _transferAssets(presentId, msg.sender);
        if (unwrappedNFT != address(0)) { IPresentNFT(unwrappedNFT).mint(msg.sender, presentId); }
        emit UnwrapPresentTest(presentId, msg.sender);
    }

    // ------------------------------------------------------------------------
    // 外部接口：寄件人收回礼物
    // 要求：仅发送者可调用；且礼物处于 ACTIVE 或者已经过期
    // 顺序：状态更新 → 统计 → 资产转移 → 事件
    // ------------------------------------------------------------------------
    function takeBack(bytes32 presentId)
        external nonReentrant whenNotPaused presentExists(presentId) onlySender(presentId)
    {
        require(_canTakeBack(presentId), "Cannot take back: gift is unwrapped or not expired");
        _setStatus(presentId, PRESENT_TAKEN_BACK);
        totalPresentsTakenBack++;
        _transferAssets(presentId, msg.sender);
        emit TakeBack(presentId, msg.sender);
    }

    // 测试/演示版本（触发 *_Test 事件）
    function takeBackTest(bytes32 presentId)
        external nonReentrant whenNotPaused presentExists(presentId) onlySender(presentId)
    {
        require(_canTakeBack(presentId), "Cannot take back: gift is unwrapped or not expired");
        _setStatus(presentId, PRESENT_TAKEN_BACK);
        totalPresentsTakenBack++;
        _transferAssets(presentId, msg.sender);
        emit TakeBackTest(presentId, msg.sender);
    }

    // 判断是否可收回：仍处于 ACTIVE，或已过期
    function _canTakeBack(bytes32 presentId) internal view returns (bool) {
        uint8 st = _getStatus(presentId);
        if (st == PRESENT_ACTIVE) return true; // 仍然激活，允许立即收回
        if (presents[presentId].expiryAt > 0 && block.timestamp > presents[presentId].expiryAt) return true; // 已过期
        return false; // 已拆包或已收回的场景
    }

    // 获取礼物状态：若存储为 ACTIVE 但已过期，则逻辑上映射为 EXPIRED（避免额外 SSTORE）
    function _getStatus(bytes32 presentId) internal view returns (uint8) {
        PresentInfo storage p = presents[presentId];
        if (p.status == PRESENT_ACTIVE && _isExpired(presentId)) return PRESENT_EXPIRED;
        return p.status;
    }

    // 设置礼物状态（内部使用）
    function _setStatus(bytes32 presentId, uint8 newStatus) internal {
        presents[presentId].status = newStatus;
    }

    // 读取工具：取发送者
    function _getSender(bytes32 presentId) internal view returns (address) {
        return presents[presentId].sender;
    }

    // 读取工具：取接收者数组
    function _getRecipients(bytes32 presentId) internal view returns (address[] memory) {
        return presents[presentId].recipients;
    }

    // 只读过期判断（被 canUnwrap/_getStatus 等调用）
    function _isExpired(bytes32 presentId) internal view returns (bool) {
        return (presents[presentId].expiryAt > 0 && block.timestamp > presents[presentId].expiryAt);
    }

    // ------------------------------------------------------------------------
    // 读接口：供前端/后端查询展示
    // ------------------------------------------------------------------------
    function getPresent(bytes32 presentId)
        external view
        returns (
            address sender,
            address[] memory recipients,
            Asset[] memory content,
            string memory title,
            string memory description,
            uint8 status,
            uint256 expiryAt
        )
    {
        PresentInfo storage p = presents[presentId];
        return (p.sender, p.recipients, p.content, p.title, p.description, _getStatus(presentId), p.expiryAt);
    }

    // 仅返回资产明细（减少无关字段传输）
    function getPresentContent(bytes32 presentId) external view returns (Asset[] memory) {
        return presents[presentId].content;
    }

    // 仅返回逻辑状态码
    function getPresentStatus(bytes32 presentId) external view returns (uint8) {
        return _getStatus(presentId);
    }

    // ------------------------------------------------------------------------
    // 礼物 ID 生成：
    // 基于（发送者/收件人数组/资产数组/时间戳/随机熵/本合约地址）生成 keccak256 哈希；
    // 使用 abi.encode（非 encodePacked）以减少编码歧义。
    // ------------------------------------------------------------------------
    function generatePresentId(address[] calldata recipients, Asset[] calldata content)
        internal view returns (bytes32)
    {
        return keccak256(abi.encode(
            msg.sender,        // 发送者
            recipients,        // 接收者列表
            content,           // 资产列表
            block.timestamp,   // 时间
            block.prevrandao,  // 随机熵（后合并时代字段）
            address(this)      // 本合约地址（防跨合约碰撞）
        ));
    }

    // ------------------------------------------------------------------------
    // 资产转移（出库）：将礼物中的所有资产转给 recipient
    // ETH 使用 call 发送；ERC20 使用 safeTransfer
    // ------------------------------------------------------------------------
    function _transferAssets(bytes32 presentId, address recipient) private {
        Asset[] memory assets = presents[presentId].content; // 读出内容到 memory
        uint256 assetsLength = assets.length;
        for (uint i = 0; i < assetsLength; i++) {
            if (assets[i].tokens == address(0)) {
                (bool success, ) = payable(recipient).call{value: assets[i].amounts}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(assets[i].tokens).safeTransfer(recipient, assets[i].amounts);
            }
        }
    }

    // ------------------------------------------------------------------------
    // 管理接口（仅所有者）：设置 NFT、黑名单、更新配置
    // ------------------------------------------------------------------------
    function setNFTContracts(address _wrappedNFT, address _unwrappedNFT) external onlyOwner {
        wrappedNFT = _wrappedNFT;
        unwrappedNFT = _unwrappedNFT;
    }

    function setTokenBlacklist(address token, bool blacklisted) external onlyOwner {
        require(token != address(0), "Cannot blacklist ETH"); // ETH 不在黑名单体系内
        blacklistedTokens[token] = blacklisted;
        emit TokenBlacklisted(token, blacklisted);
    }

    function updateConfig(uint256 _maxAssetCount, uint256 _maxRecipientCount, uint256 _defaultExpiryPeriod)
        external onlyOwner
    {
        // 发事件留档配置变更轨迹
        emit ConfigUpdated("maxAssetCount", maxAssetCount, _maxAssetCount);
        emit ConfigUpdated("maxRecipientCount", maxRecipientCount, _maxRecipientCount);
        emit ConfigUpdated("defaultExpiryPeriod", defaultExpiryPeriod, _defaultExpiryPeriod);
        // 实际更新
        maxAssetCount = _maxAssetCount;
        maxRecipientCount = _maxRecipientCount;
        defaultExpiryPeriod = _defaultExpiryPeriod;
    }

    // ------------------------------------------------------------------------
    // 紧急提取（仅所有者）：将合约中的 ETH/代币提取到 owner
    // 场景：误转入资金、合约迁移等；需配合治理/多签使用，避免滥用风险
    // ------------------------------------------------------------------------
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            require(amount <= address(this).balance, "Insufficient ETH balance");
            (bool success, ) = payable(owner()).call{value: amount}("");
            require(success, "ETH withdrawal failed");
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
        emit EmergencyWithdraw(token, owner(), amount);
    }

    // ------------------------------------------------------------------------
    // 强制过期（仅所有者）：将 ACTIVE 的礼物标记为 EXPIRED；收礼人将无法继续拆包
    // ------------------------------------------------------------------------
    function forceExpirePresent(bytes32 presentId) external onlyOwner presentExists(presentId) {
        require(_getStatus(presentId) == PRESENT_ACTIVE, "Present not active");
        _setStatus(presentId, PRESENT_EXPIRED);
        totalPresentsExpired++;
        emit PresentExpired(presentId, _getSender(presentId));
    }

    // 运营开关：暂停/恢复
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // 接收 ERC721（为未来支持 ERC721 打包做准备）；返回自身选择器表示“我能接收”
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // 便捷读接口：公开的过期检查
    function isExpired(bytes32 presentId) public view returns (bool) { return _isExpired(presentId); }

    // 接收裸 ETH（例如直接转账到合约）
    receive() external payable {}
} 