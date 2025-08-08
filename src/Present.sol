// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// 导入OpenZeppelin库
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @title Present
 * @dev 礼物包装、拆包和收回系统
 * 允许用户将ETH和ERC20代币打包成礼物，指定接收者或允许任何人领取
 */
interface IPresentNFT {
    function mint(address to, bytes32 presentId) external returns (uint256);
}

contract Present is Ownable, ReentrancyGuard, Pausable, IERC721Receiver {
    using SafeERC20 for IERC20;

    // 事件定义 - 保持原始接口
    event WrapPresent(bytes32 indexed presentId, address sender);
    event UnwrapPresent(bytes32 indexed presentId, address taker);
    event TakeBack(bytes32 indexed presentId, address sender);
    
    // 扩展事件，提供更详细的数据
    event PresentExpired(bytes32 indexed presentId, address indexed sender);
    event EmergencyWithdraw(address indexed token, address indexed to, uint256 amount);
    event TokenBlacklisted(address indexed token, bool status);
    event ConfigUpdated(string indexed paramName, uint256 oldValue, uint256 newValue);
    
    // 资产结构定义 - 保持原始接口
    struct Asset {
        address tokens;
        uint256 amounts;
    }
    
    // 扩展资产结构 - 用于内部处理NFT
    struct ExtendedAsset {
        address token;
        uint256 amount;
        bool isNFT;
        uint256 tokenId;
    }
    
    // 礼物状态常量
    uint8 private constant PRESENT_ACTIVE = 0;
    uint8 private constant PRESENT_UNWRAPPED = 1;
    uint8 private constant PRESENT_TAKEN_BACK = 2;
    uint8 private constant PRESENT_EXPIRED = 3;
    
    // 配置参数
    uint256 public maxAssetCount = 20;
    uint256 public maxRecipientCount = 100;
    uint256 public defaultExpiryPeriod = 365 days; // 默认一年有效期
    uint256 public minValueForGiftDisplay = 0; // 最小显示价值，将来可由治理设置
    
    // 状态变量 - 保持原始接口的contentOf
    mapping(bytes32 => Asset[]) public contentOf;

    // 优化的状态变量
    mapping(bytes32 => address) public senderOf;
    mapping(bytes32 => address[]) public recipientsOf;
    mapping(bytes32 => uint8) private presentStatus;  // 使用单个uint8而非多个bool，节省gas
    mapping(bytes32 => uint256) public expiryTimes;   // 礼物过期时间
    
    // 代币安全
    mapping(address => bool) public blacklistedTokens;   // 黑名单代币

    // 统计信息
    uint256 public totalPresentsWrapped;
    uint256 public totalPresentsUnwrapped;
    uint256 public totalPresentsTakenBack;
    uint256 public totalPresentsExpired;
    mapping(address => uint256) public userWrappedCount;
    mapping(address => uint256) public userUnwrappedCount;
    
    // 外部NFT合约地址
    address public wrappedNFT;
    address public unwrappedNFT;
    
    // 构造函数，设置NFT合约地址和所有者
    constructor(address initialOwner) Ownable(initialOwner) {
        // NFT合约可在部署后通过setNFTContracts设置
    }
    
    // 修饰器：检查礼物是否存在
    modifier presentExists(bytes32 presentId) {
        require(contentOf[presentId].length > 0, "Present does not exist");
        _;
    }
    
    // 修饰器：检查礼物是否可被拆开
    modifier canUnwrap(bytes32 presentId) {
        require(presentStatus[presentId] == PRESENT_ACTIVE, "Present cannot be unwrapped");
        // 检查是否过期
        if (expiryTimes[presentId] > 0 && block.timestamp > expiryTimes[presentId]) {
            presentStatus[presentId] = PRESENT_EXPIRED;
            totalPresentsExpired++;
            emit PresentExpired(presentId, senderOf[presentId]);
            revert("Present has expired");
        }
        _;
    }
    
    // 修饰器：检查是否为礼物发送者
    modifier onlySender(bytes32 presentId) {
        require(senderOf[presentId] == msg.sender, "Only sender can call this function");
        _;
    }
    
    // 修饰器：检查是否为礼物接收者
    modifier onlyRecipient(bytes32 presentId) {
        bool isRecipient = false;
        address[] memory recipients = recipientsOf[presentId];
        
        // 检查是否为任意接收者可领取
        if (recipients.length == 0) {
            isRecipient = true;
        } else {
            // 检查调用者是否在接收者列表中
            for (uint i = 0; i < recipients.length; i++) {
                if (recipients[i] == msg.sender) {
                    isRecipient = true;
                    break;
                }
            }
        }
        
        require(isRecipient, "Only recipient can unwrap this present");
        _;
    }
    
    // 修饰器：检查代币是否被黑名单
    modifier tokenNotBlacklisted(address token) {
        if (token != address(0)) { // ETH总是允许
            require(!blacklistedTokens[token], "Token is blacklisted");
        }
        _;
    }
    
    /**
     * @dev 打包礼物
     * @param recipients 礼物接收者地址列表，空数组表示任何人都可以领取
     * @param content 礼物内容（代币地址和数量）
     * 保持原始接口
     */
    function wrapPresent(address[] calldata recipients, Asset[] calldata content) 
        external 
        payable 
        nonReentrant 
        whenNotPaused 
    {
        // 数组大小限制
        require(content.length > 0 && content.length <= maxAssetCount, "Invalid content size");
        require(recipients.length <= maxRecipientCount, "Too many recipients");
        
        uint256 ethValue = 0;
        
        // 计算并验证总ETH值
        for (uint i = 0; i < content.length; i++) {
            // 检查代币是否在黑名单中
            require(!blacklistedTokens[content[i].tokens], "Contains blacklisted token");
            
            if (content[i].tokens == address(0)) {
                ethValue += content[i].amounts;
            }
            require(content[i].amounts > 0, "Amount must be positive");
        }
        
        require(msg.value >= ethValue, "Insufficient ETH sent");
        
        // 生成礼物ID
        bytes32 presentId = generatePresentId(recipients, content);
        
        // 确保礼物ID尚未使用
        require(contentOf[presentId].length == 0, "Present ID already exists");
        
        // 处理ERC20代币转账
        for (uint i = 0; i < content.length; i++) {
            if (content[i].tokens != address(0)) {
                // 使用SafeERC20安全转账
                IERC20(content[i].tokens).safeTransferFrom(
                    msg.sender, 
                    address(this), 
                    content[i].amounts
                );
            }
            
            // 存储礼物内容
            contentOf[presentId].push(content[i]);
        }
        
        // 记录礼物发送者和接收者
        senderOf[presentId] = msg.sender;
        recipientsOf[presentId] = recipients;
        presentStatus[presentId] = PRESENT_ACTIVE;
        
        // 设置过期时间
        expiryTimes[presentId] = block.timestamp + defaultExpiryPeriod;
        
        // 更新统计信息
        totalPresentsWrapped++;
        userWrappedCount[msg.sender]++;
        
        // 如果NFT合约已设置，铸造礼物NFT给发送者
        if (wrappedNFT != address(0)) {
            IPresentNFT(wrappedNFT).mint(msg.sender, presentId);
        }
        
        // 触发事件
        emit WrapPresent(presentId, msg.sender);
        
        // 退还多余的ETH
        if (msg.value > ethValue) {
            (bool success, ) = msg.sender.call{value: msg.value - ethValue}("");
            require(success, "ETH refund failed");
        }
    }
    
    /**
     * @dev 拆开礼物
     * @param presentId 礼物ID
     * 保持原始接口
     */
    function unwrapPresent(bytes32 presentId) 
        external 
        nonReentrant 
        whenNotPaused
        presentExists(presentId) 
        canUnwrap(presentId)
        onlyRecipient(presentId) 
    {
        // 先更新状态（Checks-Effects-Interactions模式）
        presentStatus[presentId] = PRESENT_UNWRAPPED;
        
        // 更新统计信息
        totalPresentsUnwrapped++;
        userUnwrappedCount[msg.sender]++;
        
        // 转移礼物中的资产给接收者
        _transferAssets(presentId, msg.sender);
        
        // 如果NFT合约已设置，铸造已拆开礼物NFT给接收者
        if (unwrappedNFT != address(0)) {
            IPresentNFT(unwrappedNFT).mint(msg.sender, presentId);
        }
        
        // 触发事件
        emit UnwrapPresent(presentId, msg.sender);
    }
    
    /**
     * @dev 收回礼物
     * @param presentId 礼物ID
     * 保持原始接口
     */
    function takeBack(bytes32 presentId) 
        external 
        nonReentrant 
        whenNotPaused
        presentExists(presentId) 
        onlySender(presentId) 
    {
        // 检查礼物状态
        require(
            presentStatus[presentId] == PRESENT_ACTIVE || 
            (expiryTimes[presentId] > 0 && block.timestamp > expiryTimes[presentId]), 
            "Cannot take back: gift is unwrapped or not expired"
        );
        
        // 先更新状态（Checks-Effects-Interactions模式）
        presentStatus[presentId] = PRESENT_TAKEN_BACK;
        
        // 更新统计信息
        totalPresentsTakenBack++;
        
        // 转移礼物中的资产回发送者
        _transferAssets(presentId, msg.sender);
        
        // 触发事件
        emit TakeBack(presentId, msg.sender);
    }

    /**
     * @dev 内部函数：转移资产给指定地址
     * @param presentId 礼物ID
     * @param recipient 接收者地址
     */
    function _transferAssets(bytes32 presentId, address recipient) private {
        Asset[] memory assets = contentOf[presentId];
        uint256 assetsLength = assets.length;
        
        for (uint i = 0; i < assetsLength; i++) {
            if (assets[i].tokens == address(0)) {
                // 转移ETH
                (bool success, ) = payable(recipient).call{value: assets[i].amounts}("");
                require(success, "ETH transfer failed");
            } else {
                // 使用SafeERC20安全转账
                IERC20(assets[i].tokens).safeTransfer(recipient, assets[i].amounts);
            }
        }
    }
    
    /**
     * @dev 生成礼物ID
     * @param recipients 接收者地址列表
     * @param content 礼物内容
     * @return 礼物ID (keccak256 hash)
     */
    function generatePresentId(address[] calldata recipients, Asset[] calldata content) 
        internal 
        view 
        returns (bytes32) 
    {
        return keccak256(abi.encode(
            msg.sender,
            recipients,
            content,
            block.timestamp,
            block.prevrandao,
            address(this)  // 增加合约地址，防止跨链重放
        ));
    }
    
    /**
     * @dev 获取礼物内容
     * @param presentId 礼物ID
     * @return 礼物资产数组
     */
    function getPresentContent(bytes32 presentId) 
        external 
        view 
        returns (Asset[] memory) 
    {
        return contentOf[presentId];
    }
    
    /**
     * @dev 获取礼物状态
     * @param presentId 礼物ID
     * @return status 0=活跃, 1=已拆开, 2=已收回, 3=已过期
     */
    function getPresentStatus(bytes32 presentId) 
        external 
        view 
        returns (uint8) 
    {
        // 检查是否过期但尚未标记
        if (
            presentStatus[presentId] == PRESENT_ACTIVE && 
            expiryTimes[presentId] > 0 && 
            block.timestamp > expiryTimes[presentId]
        ) {
            return PRESENT_EXPIRED;
        }
        return presentStatus[presentId];
    }
    
    /**
     * @dev 设置NFT合约地址（只有合约所有者可以调用）
     * @param _wrappedNFT 打包礼物NFT合约地址
     * @param _unwrappedNFT 拆开礼物NFT合约地址
     */
    function setNFTContracts(address _wrappedNFT, address _unwrappedNFT) 
        external 
        onlyOwner 
    {
        wrappedNFT = _wrappedNFT;
        unwrappedNFT = _unwrappedNFT;
    }
    
    /**
     * @dev 设置代币黑名单状态
     * @param token 代币地址
     * @param blacklisted 是否加入黑名单
     */
    function setTokenBlacklist(address token, bool blacklisted) 
        external 
        onlyOwner 
    {
        require(token != address(0), "Cannot blacklist ETH");
        blacklistedTokens[token] = blacklisted;
        emit TokenBlacklisted(token, blacklisted);
    }
    
    /**
     * @dev 更新配置参数
     * @param _maxAssetCount 最大资产数量
     * @param _maxRecipientCount 最大接收者数量
     * @param _defaultExpiryPeriod 默认过期时间(秒)
     */
    function updateConfig(
        uint256 _maxAssetCount,
        uint256 _maxRecipientCount,
        uint256 _defaultExpiryPeriod
    ) 
        external 
        onlyOwner 
    {
        emit ConfigUpdated("maxAssetCount", maxAssetCount, _maxAssetCount);
        emit ConfigUpdated("maxRecipientCount", maxRecipientCount, _maxRecipientCount);
        emit ConfigUpdated("defaultExpiryPeriod", defaultExpiryPeriod, _defaultExpiryPeriod);
        
        maxAssetCount = _maxAssetCount;
        maxRecipientCount = _maxRecipientCount;
        defaultExpiryPeriod = _defaultExpiryPeriod;
    }
    
    /**
     * @dev 紧急资产提取（只有合约所有者可用）
     * 用于提取错误发送到合约的资产，或在紧急情况下
     * @param token 代币地址（address(0)表示ETH）
     * @param amount 提取金额
     */
    function emergencyWithdraw(address token, uint256 amount) 
        external 
        onlyOwner 
    {
        if (token == address(0)) {
            require(amount <= address(this).balance, "Insufficient ETH balance");
            (bool success, ) = payable(owner()).call{value: amount}("");
            require(success, "ETH withdrawal failed");
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
        
        emit EmergencyWithdraw(token, owner(), amount);
    }
    
    /**
     * @dev 提前使礼物过期（紧急情况下使用）
     * @param presentId 礼物ID
     */
    function forceExpirePresent(bytes32 presentId) 
        external 
        onlyOwner 
        presentExists(presentId)
    {
        require(presentStatus[presentId] == PRESENT_ACTIVE, "Present not active");
        presentStatus[presentId] = PRESENT_EXPIRED;
        totalPresentsExpired++;
        
        emit PresentExpired(presentId, senderOf[presentId]);
    }
    
    /**
     * @dev 暂停合约（紧急情况使用）
     */
    function pause() external onlyOwner {
        _pause();
    }
    
    /**
     * @dev 恢复合约
     */
    function unpause() external onlyOwner {
        _unpause();
    }
    
    /**
     * @dev 支持ERC721接收
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }
    
    /**
     * @dev 检查礼物是否过期
     * @param presentId 礼物ID
     * @return 是否过期
     */
    function isExpired(bytes32 presentId) public view returns (bool) {
        return expiryTimes[presentId] > 0 && block.timestamp > expiryTimes[presentId];
    }
    
    /**
     * @dev 支持未来可能的ERC721资产支持
     * 此函数将在后续更新中实现
     */
    function setupERC721Support() external onlyOwner {
        // 预留接口，未来实现
    }
    
    /**
     * @dev 接收ETH的回退函数
     */
    receive() external payable {}
} 