// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

contract UnwrappedPresentNFT is ERC721, ERC721URIStorage, ERC721Enumerable {
    using Strings for uint256;

    address public presentContract;
    address public deployer;
    
    // 存储每个拆包NFT的礼物信息
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
    
    constructor(address _presentContract) ERC721("UnwrappedPresent", "UP") {
        presentContract = _presentContract;
        deployer = msg.sender;
    }

    // 添加设置函数，只有部署者能调用
    function setPresentContract(address _presentContract) external {
        require(msg.sender == deployer, "Only deployer can set");
        require(_presentContract != address(0), "Invalid address");
        presentContract = _presentContract;
    }

    // 修改mint函数，接收完整的拆包礼物信息
    function mint(
        address to, 
        bytes32 presentId,
        string memory giftTitle,
        string memory giftMessage,
        uint256 ethValue,
        address creator,
        uint256 tokenAmount
    ) external returns (uint256) {
        require(msg.sender == presentContract, "Only present contract can mint");
        
        uint256 tokenId = uint256(presentId);
        _mint(to, tokenId);
        
        // 存储拆包礼物信息
        unwrappedGiftInfos[tokenId] = UnwrappedGiftInfo({
            title: giftTitle,
            message: giftMessage,
            ethValue: ethValue,
            creator: creator,
            recipient: to,
            unwrappedAt: block.timestamp,
            hasTokenRewards: tokenAmount > 0,
            tokenAmount: tokenAmount
        });
        
        string memory uri = generateTokenURI(tokenId, presentId);
        _setTokenURI(tokenId, uri);
        
        return tokenId;
    }

    // 获取拆包礼物信息的公开函数
    function getUnwrappedGiftInfo(uint256 tokenId) external view returns (
        string memory title,
        string memory message,
        uint256 ethValue,
        address creator,
        address recipient,
        uint256 unwrappedAt,
        bool hasTokenRewards,
        uint256 tokenAmount
    ) {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        UnwrappedGiftInfo memory info = unwrappedGiftInfos[tokenId];
        return (
            info.title, 
            info.message, 
            info.ethValue, 
            info.creator, 
            info.recipient, 
            info.unwrappedAt,
            info.hasTokenRewards,
            info.tokenAmount
        );
    }

    function generateTokenURI(
        uint256 tokenId,
        bytes32 presentId
    ) internal view returns (string memory) {
        UnwrappedGiftInfo memory giftInfo = unwrappedGiftInfos[tokenId];
        string memory svg = generateUnwrappedSVG(tokenId, presentId, giftInfo);
        
        // 生成属性数组
        string memory attributes = string(
            abi.encodePacked(
                '[',
                    '{"trait_type": "Present ID", "value": "', uint256(presentId).toString(), '"},',
                    '{"trait_type": "Type", "value": "Unwrapped"},',
                    '{"trait_type": "ETH Value", "value": "', (giftInfo.ethValue / 1e15).toString(), '"},',
                    '{"trait_type": "Creator", "value": "', Strings.toHexString(uint160(giftInfo.creator), 20), '"},',
                    '{"trait_type": "Recipient", "value": "', Strings.toHexString(uint160(giftInfo.recipient), 20), '"},',
                    '{"trait_type": "Unwrapped Date", "value": "', giftInfo.unwrappedAt.toString(), '"},',
                    '{"trait_type": "Has Token Rewards", "value": "', giftInfo.hasTokenRewards ? "Yes" : "No", '"}'
            )
        );
        
        if (giftInfo.hasTokenRewards) {
            attributes = string(
                abi.encodePacked(
                    attributes,
                    ',{"trait_type": "Token Amount", "value": "', giftInfo.tokenAmount.toString(), '"}'
                )
            );
        }
        
        attributes = string(abi.encodePacked(attributes, ']'));
        
        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "', giftInfo.title, ' (Unwrapped)",',
                        '"description": "', giftInfo.message, ' This gift has been unwrapped and the contents have been claimed!",',
                        '"image": "data:image/svg+xml;base64,', Base64.encode(bytes(svg)), '",',
                        '"attributes": ', attributes,
                        '}'
                    )
                )
            )
        );
        
        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    function generateUnwrappedSVG(
        uint256 tokenId,
        bytes32 presentId,
        UnwrappedGiftInfo memory giftInfo
    ) internal pure returns (string memory) {
        // 根据ETH价值调整背景颜色和星星数量
        string memory bgColor = giftInfo.ethValue >= 1e18 ? "#ff6b6b" : giftInfo.ethValue >= 1e16 ? "#ffa500" : "#ff69b4";
        string memory glowColor = giftInfo.ethValue >= 1e18 ? "#ffcccc" : "#ffe0b3";
        
        // 截断长标题用于显示
        string memory displayTitle = bytes(giftInfo.title).length > 18 ? 
            string(abi.encodePacked(substring(giftInfo.title, 0, 15), "...")) : 
            giftInfo.title;
            
        // 生成星星装饰
        string memory stars = generateStars(giftInfo.ethValue);
        
        return string(
            abi.encodePacked(
                '<svg width="400" height="400" xmlns="http://www.w3.org/2000/svg">',
                '<defs>',
                    '<radialGradient id="bg" cx="50%" cy="50%" r="50%">',
                        '<stop offset="0%" style="stop-color:', glowColor, ';stop-opacity:0.8"/>',
                        '<stop offset="100%" style="stop-color:#f0f8ff;stop-opacity:1"/>',
                    '</radialGradient>',
                    '<filter id="glow">',
                        '<feGaussianBlur stdDeviation="3" result="coloredBlur"/>',
                        '<feMerge><feMergeNode in="coloredBlur"/><feMergeNode in="SourceGraphic"/></feMerge>',
                    '</filter>',
                '</defs>',
                '<rect width="400" height="400" fill="url(#bg)"/>',
                stars,
                '<circle cx="200" cy="200" r="120" fill="', bgColor, '" opacity="0.9" filter="url(#glow)"/>',
                '<circle cx="200" cy="200" r="100" fill="none" stroke="#ffffff" stroke-width="3" opacity="0.7"/>',
                '<text x="200" y="180" text-anchor="middle" font-family="Arial" font-size="20" fill="white" font-weight="bold">',
                displayTitle,
                '</text>',
                '<text x="200" y="205" text-anchor="middle" font-family="Arial" font-size="14" fill="white">',
                'Unwrapped!',
                '</text>',
                '<text x="200" y="225" text-anchor="middle" font-family="Arial" font-size="12" fill="white">',
                'Value: ', (giftInfo.ethValue / 1e15).toString(), ' mETH',
                '</text>',
                giftInfo.hasTokenRewards ? 
                    '<text x="200" y="245" text-anchor="middle" font-family="Arial" font-size="10" fill="white">+ Token Rewards</text>' : 
                    '',
                '<text x="200" y="270" text-anchor="middle" font-family="Arial" font-size="10" fill="white" opacity="0.8">',
                'Token #', tokenId.toString(),
                '</text>',
                '</svg>'
            )
        );
    }
    
    // 生成星星装饰（根据价值决定数量）
    function generateStars(uint256 ethValue) internal pure returns (string memory) {
        uint256 starCount = ethValue >= 1e18 ? 8 : ethValue >= 1e16 ? 5 : 3;
        string memory stars = "";
        
        // 简化的星星位置（预定义）
        if (starCount >= 3) {
            stars = string(abi.encodePacked(
                stars,
                '<circle cx="100" cy="100" r="2" fill="#ffff00" opacity="0.8"/>',
                '<circle cx="300" cy="120" r="2" fill="#ffff00" opacity="0.8"/>',
                '<circle cx="80" cy="300" r="2" fill="#ffff00" opacity="0.8"/>'
            ));
        }
        if (starCount >= 5) {
            stars = string(abi.encodePacked(
                stars,
                '<circle cx="320" cy="280" r="2" fill="#ffff00" opacity="0.8"/>',
                '<circle cx="150" cy="80" r="2" fill="#ffff00" opacity="0.8"/>'
            ));
        }
        if (starCount >= 8) {
            stars = string(abi.encodePacked(
                stars,
                '<circle cx="60" cy="150" r="2" fill="#ffff00" opacity="0.8"/>',
                '<circle cx="340" cy="200" r="2" fill="#ffff00" opacity="0.8"/>',
                '<circle cx="200" cy="60" r="2" fill="#ffff00" opacity="0.8"/>'
            ));
        }
        
        return stars;
    }
    
    // 辅助函数：字符串截取
    function substring(string memory str, uint startIndex, uint endIndex) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return string(result);
    }

    // 重写tokenURI函数以支持动态元数据
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        
        // 如果没有设置URI，则生成动态URI
        string memory _tokenURI = super.tokenURI(tokenId);
        if (bytes(_tokenURI).length == 0) {
            return generateTokenURI(tokenId, bytes32(tokenId));
        }
        return _tokenURI;
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