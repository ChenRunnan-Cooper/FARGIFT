// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// Present 合约的只读接口，完全匹配主合约
interface IPresentViewU {
    struct Asset {
        address tokens;
        uint256 amounts;
    }
    enum DistributionType {
        FIRST_COME_FIRST_SERVED,
        LIMITED_QUANTITY_EQUAL_SPLIT,
        WHITELIST_EQUAL_SPLIT,
        LIMITED_QUANTITY_RANDOM_SPLIT
    }
    function getPresent(bytes32 presentId)
        external view
        returns (
            address sender,
            string memory title,
            string memory description,
            uint8 status,
            uint256 expiryAt,
            DistributionType distType,
            uint256 claimLimit,
            uint256 claimedCount
        );
    function getPresentContent(bytes32 presentId) external view returns (Asset[] memory);
}

// 【绝对正确的继承顺序】：ERC721 → ERC721Enumerable → ERC721URIStorage → Ownable
contract UnwrappedPresentNFT is ERC721, ERC721Enumerable, ERC721URIStorage, Ownable {
    using Strings for uint256;

    address payable public presentContract;
    address public deployer;

    struct UnwrappedGiftInfo {
        string title;
        string message;
        uint256 ethValue;
        address creator;
        address recipient;
        uint256 unwrappedAt;
        bool hasTokenRewards;
        uint256 tokenAmount;
    }

    mapping(uint256 => UnwrappedGiftInfo) public unwrappedGiftInfos;
    
    // 新增事件
    event PresentNFTMinted(address indexed to, bytes32 indexed presentId, uint256 indexed tokenId);
    event PresentContractUpdated(address indexed oldContract, address indexed newContract);
    event TokenURIRequested(uint256 indexed tokenId);
    event UnwrappedGiftInfoStored(uint256 indexed tokenId, string title, uint256 ethValue);
    
    constructor(address _presentContract, address initialOwner) 
        ERC721("UnwrappedPresent", "UP") 
        Ownable(initialOwner) 
    {
        require(_presentContract != address(0), "Invalid present contract");
        presentContract = payable(_presentContract);
        deployer = msg.sender;
        emit PresentContractUpdated(address(0), _presentContract);
    }

    function setPresentContract(address _presentContract) external onlyOwner {
        require(_presentContract != address(0), "Invalid address");
        address oldContract = presentContract;
        presentContract = payable(_presentContract);
        emit PresentContractUpdated(oldContract, _presentContract);
    }

    function mint(address to, bytes32 presentId) external returns (uint256) {
        require(msg.sender == presentContract, "Only present contract can mint");
        require(to != address(0), "Invalid recipient");
        
        IPresentViewU present = IPresentViewU(presentContract);
        (address sender, string memory title, string memory description,,,,,) = present.getPresent(presentId);
        IPresentViewU.Asset[] memory content = present.getPresentContent(presentId);
        
        uint256 ethValue = 0;
        bool hasTokenRewards = false;
        uint256 tokenAmount = 0;
        
        for (uint i = 0; i < content.length; i++) {
            if (content[i].tokens == address(0)) {
                ethValue += content[i].amounts;
            } else {
                hasTokenRewards = true;
                if (tokenAmount == 0) {
                    tokenAmount = content[i].amounts;
                }
            }
        }
        
        uint256 tokenId = uint256(presentId);
        _mint(to, tokenId);
        
        unwrappedGiftInfos[tokenId] = UnwrappedGiftInfo({
            title: title,
            message: description,
            ethValue: ethValue,
            creator: sender,
            recipient: to,
            unwrappedAt: block.timestamp,
            hasTokenRewards: hasTokenRewards,
            tokenAmount: tokenAmount
        });
        
        string memory uri = generateTokenURI(tokenId, presentId);
        _setTokenURI(tokenId, uri);
        
        emit PresentNFTMinted(to, presentId, tokenId);
        emit UnwrappedGiftInfoStored(tokenId, title, ethValue);
        
        return tokenId;
    }

    function getUnwrappedGiftInfo(uint256 tokenId) external view returns (
        string memory title, string memory message, uint256 ethValue,
        address creator, address recipient, uint256 unwrappedAt,
        bool hasTokenRewards, uint256 tokenAmount
    ) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        UnwrappedGiftInfo memory info = unwrappedGiftInfos[tokenId];
        return (
            info.title, info.message, info.ethValue, 
            info.creator, info.recipient, info.unwrappedAt,
            info.hasTokenRewards, info.tokenAmount
        );
    }

    function generateTokenURI(uint256 tokenId, bytes32 presentId) internal view returns (string memory) {
        UnwrappedGiftInfo memory giftInfo = unwrappedGiftInfos[tokenId];
        string memory ipfsImageUrl = "https://ipfs.io/ipfs/QmZzNo1otv1fAjURQqGiBjDCZ6AwN91wVzZmonKsP48TPh";
        
        string memory attributes = string(abi.encodePacked(
            '[',
                '{"trait_type": "Present ID", "value": "', uint256(presentId).toString(), '"},',
                '{"trait_type": "Type", "value": "Unwrapped"},',
                '{"trait_type": "ETH Value", "value": "', (giftInfo.ethValue / 1e15).toString(), ' mETH"},',
                '{"trait_type": "Creator", "value": "', Strings.toHexString(uint160(giftInfo.creator), 20), '"},',
                '{"trait_type": "Recipient", "value": "', Strings.toHexString(uint160(giftInfo.recipient), 20), '"},',
                '{"trait_type": "Unwrapped Date", "value": "', giftInfo.unwrappedAt.toString(), '"},',
                '{"trait_type": "Has Token Rewards", "value": "', giftInfo.hasTokenRewards ? "Yes" : "No", '"}'
            ']'
        ));
        
        if (giftInfo.hasTokenRewards) {
            attributes = string(abi.encodePacked(
                attributes,
                ',{"trait_type": "Token Amount", "value": "', giftInfo.tokenAmount.toString(), '"}'
            ));
        }
        
        string memory json = Base64.encode(bytes(string(abi.encodePacked(
            '{"name": "', giftInfo.title, ' (Unwrapped)",',
            '"description": "', giftInfo.message, ' This gift has been unwrapped and the contents have been claimed!",',
            '"image": "', ipfsImageUrl, '",',
            '"attributes": ', attributes,
            '}'
        ))));
        
        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    // 【修复1】移除不再需要的 _beforeTokenTransfer

    // 【修复2】移除不再需要的 _burn

    // 【修复3】supportsInterface：包含所有父合约
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // 【修复4】tokenURI：override ERC721 + ERC721URIStorage
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        // emit TokenURIRequested(tokenId); // Removed to comply with 'view' function constraints
        string memory _tokenURI = super.tokenURI(tokenId);
        if (bytes(_tokenURI).length == 0) {
            return generateTokenURI(tokenId, bytes32(tokenId));
        }
        return _tokenURI;
    }

    // 【修复5】_update：override ERC721 + ERC721Enumerable
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    // 【修复6】_increaseBalance：override ERC721 + ERC721Enumerable
    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }
}