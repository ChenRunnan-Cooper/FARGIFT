// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract WrappedPresentNFT is ERC721, ERC721URIStorage, ERC721Enumerable {
    using Strings for uint256;

    // 事件定义
    event PresentContractSet(address indexed oldContract, address indexed newContract);
    event WrappedGiftMinted(
        uint256 indexed tokenId,
        address indexed recipient,
        address indexed creator,
        string title,
        uint256 ethValue,
        uint256 createdAt
    );
    event TokenURIUpdated(uint256 indexed tokenId, string newURI);

    address public presentContract;
    address public deployer;
    
    // 存储每个NFT的礼物信息（用于查询和展示）
    struct GiftInfo {
        string title;
        string message;
        uint256 ethValue;
        address creator;
        uint256 createdAt;
        uint256 expiryAt;
    }
    
    mapping(uint256 => GiftInfo) public giftInfos;
    
    constructor() ERC721("WrappedPresent", "WP") {
        deployer = msg.sender;
    }

    // 设置Present合约地址，只有部署者能调用
    function setPresentContract(address _presentContract) external {
        require(msg.sender == deployer, "Only deployer can set");
        require(_presentContract != address(0), "Invalid address");
        
        address oldContract = presentContract;
        presentContract = _presentContract;
        
        emit PresentContractSet(oldContract, _presentContract);
    }

    // 修复后的标准mint函数 - 只接收URI
    function mint(
        address to, 
        bytes32 presentId,
        string memory tokenURI
    ) external returns (uint256) {
        require(msg.sender == presentContract, "Only present contract can mint");
        require(to != address(0), "Cannot mint to zero address");
        
        uint256 tokenId = uint256(presentId);
        _mint(to, tokenId);
        _setTokenURI(tokenId, tokenURI);
        
        return tokenId;
    }

    // 扩展mint函数 - 包含礼物信息
    function mintWithGiftInfo(
        address to, 
        bytes32 presentId,
        string memory tokenURI,
        string memory giftTitle,
        string memory giftMessage,
        uint256 ethValue,
        address creator,
        uint256 expiryAt
    ) external returns (uint256) {
        require(msg.sender == presentContract, "Only present contract can mint");
        require(to != address(0), "Cannot mint to zero address");
        
        uint256 tokenId = uint256(presentId);
        _mint(to, tokenId);
        _setTokenURI(tokenId, tokenURI);
        
        // 存储礼物信息
        giftInfos[tokenId] = GiftInfo({
            title: giftTitle,
            message: giftMessage,
            ethValue: ethValue,
            creator: creator,
            createdAt: block.timestamp,
            expiryAt: expiryAt
        });
        
        // 触发包装礼物铸造事件
        emit WrappedGiftMinted(
            tokenId,
            to,
            creator,
            giftTitle,
            ethValue,
            block.timestamp
        );
        
        return tokenId;
    }

    // 获取礼物信息
    function getGiftInfo(uint256 tokenId) external view returns (
        string memory title,
        string memory message,
        uint256 ethValue,
        address creator,
        uint256 createdAt,
        uint256 expiryAt
    ) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        GiftInfo memory info = giftInfos[tokenId];
        return (
            info.title, 
            info.message, 
            info.ethValue, 
            info.creator,
            info.createdAt,
            info.expiryAt
        );
    }

    // 管理员更新URI，触发事件
    function setTokenURI(uint256 tokenId, string memory uri) external {
        require(msg.sender == deployer || msg.sender == presentContract, "Not authorized");
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        _setTokenURI(tokenId, uri);
        emit TokenURIUpdated(tokenId, uri);
    }

    // 查询用户拥有的所有tokenId
    function tokensOfOwner(address owner) external view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(owner);
        uint256[] memory tokenIds = new uint256[](tokenCount);
        
        for (uint256 i = 0; i < tokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(owner, i);
        }
        
        return tokenIds;
    }

    // 标准tokenURI函数
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return super.tokenURI(tokenId);
    }

    // Override functions
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
