// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @title Present
 * @dev 礼物包装、拆包和收回系统；支持 ETH 与 ERC20 托管，并通过标准NFT进行状态凭证化
 */

// 标准NFT铸造接口
interface IPresentNFT {
    function mint(address to, bytes32 presentId, string memory tokenURI) external returns (uint256);
    function mintWithGiftInfo(
        address to, 
        bytes32 presentId,
        string memory tokenURI,
        string memory giftTitle,
        string memory giftMessage,
        uint256 ethValue,
        address creator,
        uint256 extraParam
    ) external returns (uint256);
}

contract Present is Ownable, ReentrancyGuard, Pausable, IERC721Receiver {
    using SafeERC20 for IERC20;

    // 事件 - 增强版本，包含更多索引信息
    event WrapPresent(
        bytes32 indexed presentId, 
        address indexed sender, 
        uint256 indexed ethValue,
        address[] recipients,
        string title,
        uint256 expiryAt
    );
    event UnwrapPresent(
        bytes32 indexed presentId, 
        address indexed taker,
        address indexed sender,
        uint256 ethValue,
        string title
    );
    event TakeBack(
        bytes32 indexed presentId, 
        address indexed sender,
        uint256 ethValue,
        string title
    );
    event WrapPresentTest(
        bytes32 indexed presentId, 
        address indexed sender,
        uint256 indexed ethValue,
        address[] recipients,
        string title
    );
    event UnwrapPresentTest(
        bytes32 indexed presentId, 
        address indexed taker,
        address indexed sender,
        uint256 ethValue
    );
    event TakeBackTest(
        bytes32 indexed presentId, 
        address indexed sender,
        uint256 ethValue
    );
    event PresentExpired(bytes32 indexed presentId, address indexed sender);
    event EmergencyWithdraw(address indexed token, address indexed to, uint256 amount);
    event TokenBlacklisted(address indexed token, bool status);
    event ConfigUpdated(string indexed paramName, uint256 oldValue, uint256 newValue);

    // 数据结构
    struct Asset {
        address tokens;   // 资产合约地址；address(0) 表示 ETH
        uint256 amounts;  // 数量
    }

    struct PresentInfo {
        bytes32 id;             
        address sender;         
        address[] recipients;   
        Asset[] content;        
        string title;           
        string description;     
        uint8 status;           // 0 active, 1 unwrapped, 2 takenBack, 3 expired
        uint256 createdAt;      
        uint256 expiryAt;       
    }

    // 状态常量
    uint8 private constant PRESENT_ACTIVE = 0;
    uint8 private constant PRESENT_UNWRAPPED = 1;
    uint8 private constant PRESENT_TAKEN_BACK = 2;
    uint8 private constant PRESENT_EXPIRED = 3;

    // 配置参数
    uint256 public maxAssetCount = 20;
    uint256 public maxRecipientCount = 100;
    uint256 public defaultExpiryPeriod = 365 days;
    uint256 public minValueForGiftDisplay = 0;

    // 主存储
    mapping(bytes32 => PresentInfo) public presents;
    mapping(address => bool) public blacklistedTokens;

    // 新增：用户礼物索引
    mapping(address => bytes32[]) public userSentPresents;
    mapping(address => bytes32[]) public userReceivedPresents;
    mapping(bytes32 => bool) private presentIndexed; // 防止重复索引

    // 统计信息
    uint256 public totalPresentsWrapped;
    uint256 public totalPresentsUnwrapped;
    uint256 public totalPresentsTakenBack;
    uint256 public totalPresentsExpired;
    mapping(address => uint256) public userWrappedCount;
    mapping(address => uint256) public userUnwrappedCount;

    // NFT合约地址
    address public wrappedNFT;
    address public unwrappedNFT;
    
    // 元数据基础URL（用于生成tokenURI）
    string public baseMetadataURI = "https://api.yourapp.com/metadata/";

    constructor(address initialOwner) Ownable(initialOwner) {}

    // 修饰符
    modifier presentExists(bytes32 presentId) {
        require(presents[presentId].sender != address(0), "Present does not exist");
        _;
    }

    modifier canUnwrap(bytes32 presentId) {
        if (_isExpired(presentId)) {
            _setStatus(presentId, PRESENT_EXPIRED);
            totalPresentsExpired++;
            emit PresentExpired(presentId, _getSender(presentId));
            revert("Present has expired");
        }
        uint8 status = _getStatus(presentId);
        require(status == PRESENT_ACTIVE, "Present cannot be unwrapped");
        _;
    }

    modifier onlySender(bytes32 presentId) {
        require(_getSender(presentId) == msg.sender, "Only sender can call this function");
        _;
    }

    modifier onlyRecipient(bytes32 presentId) {
        address[] memory recipients = _getRecipients(presentId);
        bool isRecipient = recipients.length == 0;
        if (!isRecipient) {
            for (uint i = 0; i < recipients.length; i++) {
                if (recipients[i] == msg.sender) { isRecipient = true; break; }
            }
        }
        require(isRecipient, "Only recipient can unwrap this present");
        _;
    }

    // 外部接口
    function wrapPresent(address[] calldata recipients, Asset[] calldata content)
        external payable nonReentrant whenNotPaused
    {
        _wrap({recipients: recipients, title: "", description: "", content: content, emitTest: false});
    }

    function wrapPresentTest(
        address[] calldata recipients,
        string calldata title,
        string calldata description,
        Asset[] calldata content
    ) external payable nonReentrant whenNotPaused {
        _wrap({recipients: recipients, title: title, description: description, content: content, emitTest: true});
    }

    // 核心打包逻辑
    function _wrap(
        address[] calldata recipients,
        string memory title,
        string memory description,
        Asset[] calldata content,
        bool emitTest
    ) internal {
        require(content.length > 0 && content.length <= maxAssetCount, "Invalid content size");
        require(recipients.length <= maxRecipientCount, "Too many recipients");

        uint256 ethValue = 0;
        for (uint i = 0; i < content.length; i++) {
            require(!blacklistedTokens[content[i].tokens], "Contains blacklisted token");
            if (content[i].tokens == address(0)) { ethValue += content[i].amounts; }
            require(content[i].amounts > 0, "Amount must be positive");
        }
        require(msg.value >= ethValue, "Insufficient ETH sent");

        bytes32 presentId = generatePresentId(recipients, content);
        require(presents[presentId].sender == address(0), "Present ID exists");

        // 托管ERC20
        for (uint i = 0; i < content.length; i++) {
            if (content[i].tokens != address(0)) {
                IERC20(content[i].tokens).safeTransferFrom(msg.sender, address(this), content[i].amounts);
            }
        }

        // 写入存储
        PresentInfo storage p = presents[presentId];
        p.id = presentId;
        p.sender = msg.sender;
        p.recipients = recipients;
        p.title = title;
        p.description = description;
        p.status = PRESENT_ACTIVE;
        p.createdAt = block.timestamp;
        p.expiryAt = block.timestamp + defaultExpiryPeriod;
        for (uint i2 = 0; i2 < content.length; i2++) { p.content.push(content[i2]); }

        // 新增：更新用户索引
        _indexPresent(presentId, msg.sender, recipients);

        // 统计
        totalPresentsWrapped++;
        userWrappedCount[msg.sender]++;

        // 铸造NFT（使用标准接口）
        if (wrappedNFT != address(0)) {
            string memory tokenURI = _generateWrappedTokenURI(presentId, ethValue, title);
            
            // 尝试使用扩展mint函数，如果失败则使用标准mint
            try IPresentNFT(wrappedNFT).mintWithGiftInfo(
                msg.sender, 
                presentId, 
                tokenURI,
                title,
                description,
                ethValue,
                msg.sender,
                p.expiryAt
            ) {} catch {
                IPresentNFT(wrappedNFT).mint(msg.sender, presentId, tokenURI);
            }
        }

        // 增强事件
        if (emitTest) {
            emit WrapPresentTest(presentId, msg.sender, ethValue, recipients, title);
        } else {
            emit WrapPresent(presentId, msg.sender, ethValue, recipients, title, p.expiryAt);
        }

        // 退回多余ETH
        if (msg.value > ethValue) {
            (bool success, ) = msg.sender.call{value: msg.value - ethValue}("");
            require(success, "ETH refund failed");
        }
    }

    // 新增：索引礼物到用户列表
    function _indexPresent(bytes32 presentId, address sender, address[] calldata recipients) internal {
        if (!presentIndexed[presentId]) {
            userSentPresents[sender].push(presentId);
            
            // 为每个接收者添加索引
            for (uint i = 0; i < recipients.length; i++) {
                if (recipients[i] != address(0)) {
                    userReceivedPresents[recipients[i]].push(presentId);
                }
            }
            // 如果没有指定接收者，表示任何人都可以领取，不添加到特定用户的接收列表
            
            presentIndexed[presentId] = true;
        }
    }

    // 拆包接口
    function unwrapPresent(bytes32 presentId)
        external nonReentrant whenNotPaused presentExists(presentId) canUnwrap(presentId) onlyRecipient(presentId)
    {
        _unwrap(presentId, false);
    }

    function unwrapPresentTest(bytes32 presentId)
        external nonReentrant whenNotPaused presentExists(presentId) canUnwrap(presentId) onlyRecipient(presentId)
    {
        _unwrap(presentId, true);
    }

    function _unwrap(bytes32 presentId, bool emitTest) internal {
        PresentInfo memory p = presents[presentId];
        uint256 totalEthValue = _calculateTotalEthValue(presentId);
        uint256 totalTokenAmount = _calculateTotalTokenAmount(presentId);
        
        _setStatus(presentId, PRESENT_UNWRAPPED);
        totalPresentsUnwrapped++;
        userUnwrappedCount[msg.sender]++;
        
        _transferAssets(presentId, msg.sender);

        // 铸造拆包NFT
        if (unwrappedNFT != address(0)) {
            string memory tokenURI = _generateUnwrappedTokenURI(presentId, totalEthValue, p.title);
            
            try IPresentNFT(unwrappedNFT).mintWithGiftInfo(
                msg.sender, 
                presentId, 
                tokenURI,
                p.title,
                p.description,
                totalEthValue,
                p.sender,
                totalTokenAmount
            ) {} catch {
                IPresentNFT(unwrappedNFT).mint(msg.sender, presentId, tokenURI);
            }
        }

        // 增强事件
        if (emitTest) {
            emit UnwrapPresentTest(presentId, msg.sender, p.sender, totalEthValue);
        } else {
            emit UnwrapPresent(presentId, msg.sender, p.sender, totalEthValue, p.title);
        }
    }

    // 收回接口
    function takeBack(bytes32 presentId)
        external nonReentrant whenNotPaused presentExists(presentId) onlySender(presentId)
    {
        require(_canTakeBack(presentId), "Cannot take back: gift is unwrapped or not expired");
        
        PresentInfo memory p = presents[presentId];
        uint256 totalEthValue = _calculateTotalEthValue(presentId);
        
        _setStatus(presentId, PRESENT_TAKEN_BACK);
        totalPresentsTakenBack++;
        _transferAssets(presentId, msg.sender);
        
        emit TakeBack(presentId, msg.sender, totalEthValue, p.title);
    }

    function takeBackTest(bytes32 presentId)
        external nonReentrant whenNotPaused presentExists(presentId) onlySender(presentId)
    {
        require(_canTakeBack(presentId), "Cannot take back: gift is unwrapped or not expired");
        
        uint256 totalEthValue = _calculateTotalEthValue(presentId);
        
        _setStatus(presentId, PRESENT_TAKEN_BACK);
        totalPresentsTakenBack++;
        _transferAssets(presentId, msg.sender);
        
        emit TakeBackTest(presentId, msg.sender, totalEthValue);
    }

    // 新增：预览功能 - 让前端可以预先计算presentId
    function previewPresentId(address[] calldata recipients, Asset[] calldata content)
        external view returns (bytes32) 
    {
        return keccak256(abi.encode(
            msg.sender,
            recipients,
            content,
            block.timestamp,
            block.prevrandao,
            address(this)
        ));
    }

    // 新增：查询用户创建的礼物（支持分页）
    function getUserSentPresents(address user, uint256 offset, uint256 limit) 
        external view returns (bytes32[] memory presentIds, uint256 total) 
    {
        bytes32[] memory allPresents = userSentPresents[user];
        total = allPresents.length;
        
        if (offset >= total) {
            return (new bytes32[](0), total);
        }
        
        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }
        
        uint256 length = end - offset;
        presentIds = new bytes32[](length);
        
        for (uint256 i = 0; i < length; i++) {
            presentIds[i] = allPresents[offset + i];
        }
    }

    // 新增：查询用户收到的礼物（支持分页）
    function getUserReceivedPresents(address user, uint256 offset, uint256 limit) 
        external view returns (bytes32[] memory presentIds, uint256 total) 
    {
        bytes32[] memory allPresents = userReceivedPresents[user];
        total = allPresents.length;
        
        if (offset >= total) {
            return (new bytes32[](0), total);
        }
        
        uint256 end = offset + limit;
        if (end > total) {
            end = total;
        }
        
        uint256 length = end - offset;
        presentIds = new bytes32[](length);
        
        for (uint256 i = 0; i < length; i++) {
            presentIds[i] = allPresents[offset + i];
        }
    }

    // 新增：批量查询礼物信息
    function getBatchPresentInfo(bytes32[] calldata presentIds) 
        external view returns (
            address[] memory senders,
            string[] memory titles,
            uint8[] memory statuses,
            uint256[] memory ethValues,
            uint256[] memory expiryAts
        ) 
    {
        uint256 length = presentIds.length;
        senders = new address[](length);
        titles = new string[](length);
        statuses = new uint8[](length);
        ethValues = new uint256[](length);
        expiryAts = new uint256[](length);
        
        for (uint256 i = 0; i < length; i++) {
            PresentInfo storage p = presents[presentIds[i]];
            senders[i] = p.sender;
            titles[i] = p.title;
            statuses[i] = _getStatus(presentIds[i]);
            ethValues[i] = _calculateTotalEthValue(presentIds[i]);
            expiryAts[i] = p.expiryAt;
        }
    }

    // 生成tokenURI的函数
    function _generateWrappedTokenURI(bytes32 presentId, uint256 ethValue, string memory title) 
        internal view returns (string memory) {
        return string(abi.encodePacked(
            baseMetadataURI, 
            "wrapped/", 
            _uint256ToString(uint256(presentId))
        ));
    }

    function _generateUnwrappedTokenURI(bytes32 presentId, uint256 ethValue, string memory title) 
        internal view returns (string memory) {
        return string(abi.encodePacked(
            baseMetadataURI, 
            "unwrapped/", 
            _uint256ToString(uint256(presentId))
        ));
    }

    // 工具函数
    function _calculateTotalEthValue(bytes32 presentId) internal view returns (uint256) {
        Asset[] memory assets = presents[presentId].content;
        uint256 total = 0;
        for (uint i = 0; i < assets.length; i++) {
            if (assets[i].tokens == address(0)) {
                total += assets[i].amounts;
            }
        }
        return total;
    }

    function _calculateTotalTokenAmount(bytes32 presentId) internal view returns (uint256) {
        Asset[] memory assets = presents[presentId].content;
        uint256 total = 0;
        for (uint i = 0; i < assets.length; i++) {
            if (assets[i].tokens != address(0)) {
                total += assets[i].amounts; // 简化计算，实际应用中可能需要更复杂的逻辑
            }
        }
        return total;
    }

    function _uint256ToString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    function _canTakeBack(bytes32 presentId) internal view returns (bool) {
        uint8 st = _getStatus(presentId);
        if (st == PRESENT_ACTIVE) return true;
        if (presents[presentId].expiryAt > 0 && block.timestamp > presents[presentId].expiryAt) return true;
        return false;
    }

    function _getStatus(bytes32 presentId) internal view returns (uint8) {
        PresentInfo storage p = presents[presentId];
        if (p.status == PRESENT_ACTIVE && _isExpired(presentId)) return PRESENT_EXPIRED;
        return p.status;
    }

    function _setStatus(bytes32 presentId, uint8 newStatus) internal {
        presents[presentId].status = newStatus;
    }

    function _getSender(bytes32 presentId) internal view returns (address) {
        return presents[presentId].sender;
    }

    function _getRecipients(bytes32 presentId) internal view returns (address[] memory) {
        return presents[presentId].recipients;
    }

    function _isExpired(bytes32 presentId) internal view returns (bool) {
        return (presents[presentId].expiryAt > 0 && block.timestamp > presents[presentId].expiryAt);
    }

    // 改进：将generatePresentId改为public，方便前端调用
    function generatePresentId(address[] calldata recipients, Asset[] calldata content)
        public view returns (bytes32)
    {
        return keccak256(abi.encode(
            msg.sender,
            recipients,
            content,
            block.timestamp,
            block.prevrandao,
            address(this)
        ));
    }

    // 读接口
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

    function getPresentContent(bytes32 presentId) external view returns (Asset[] memory) {
        return presents[presentId].content;
    }

    function getPresentStatus(bytes32 presentId) external view returns (uint8) {
        return _getStatus(presentId);
    }

    function _transferAssets(bytes32 presentId, address recipient) private {
        Asset[] memory assets = presents[presentId].content;
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

    // 管理接口
    function setNFTContracts(address _wrappedNFT, address _unwrappedNFT) external onlyOwner {
        wrappedNFT = _wrappedNFT;
        unwrappedNFT = _unwrappedNFT;
    }

    function setBaseMetadataURI(string memory _baseURI) external onlyOwner {
        baseMetadataURI = _baseURI;
    }

    function setTokenBlacklist(address token, bool blacklisted) external onlyOwner {
        require(token != address(0), "Cannot blacklist ETH");
        blacklistedTokens[token] = blacklisted;
        emit TokenBlacklisted(token, blacklisted);
    }

    function updateConfig(uint256 _maxAssetCount, uint256 _maxRecipientCount, uint256 _defaultExpiryPeriod)
        external onlyOwner
    {
        emit ConfigUpdated("maxAssetCount", maxAssetCount, _maxAssetCount);
        emit ConfigUpdated("maxRecipientCount", maxRecipientCount, _maxRecipientCount);
        emit ConfigUpdated("defaultExpiryPeriod", defaultExpiryPeriod, _defaultExpiryPeriod);
        
        maxAssetCount = _maxAssetCount;
        maxRecipientCount = _maxRecipientCount;
        defaultExpiryPeriod = _defaultExpiryPeriod;
    }

    // 紧急提取
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

    // 强制过期
    function forceExpirePresent(bytes32 presentId) external onlyOwner presentExists(presentId) {
        require(_getStatus(presentId) == PRESENT_ACTIVE, "Present not active");
        _setStatus(presentId, PRESENT_EXPIRED);
        totalPresentsExpired++;
        emit PresentExpired(presentId, _getSender(presentId));
    }

    // 运营开关
    function pause() external onlyOwner { _pause(); }
    function unpause() external onlyOwner { _unpause(); }

    // 接收ERC721
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    // 便捷读接口
    function isExpired(bytes32 presentId) public view returns (bool) { 
        return _isExpired(presentId); 
    }

    // 接收裸ETH
    receive() external payable {}
}