// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

// --- 新增：Present 合约的只读接口 ---
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

contract UnwrappedPresentNFT is ERC721, ERC721URIStorage, ERC721Enumerable {
    using Strings for uint256;

    address public presentContract;
    address public deployer;
    
    // --- 移除 UnwrappedGiftInfo 结构体和 mapping ---
    
    constructor(address _presentContract) ERC721("UnwrappedPresent", "UP") {
        presentContract = _presentContract;
        deployer = msg.sender;
    }

    function setPresentContract(address _presentContract) external {
        require(msg.sender == deployer, "Only deployer can set");
        require(_presentContract != address(0), "Invalid address");
        presentContract = _presentContract;
    }

    // --- 简化 mint 函数 ---
    function mint(
        address to, 
        bytes32 presentId
    ) external returns (uint256) {
        require(msg.sender == presentContract, "Only present contract can mint");
        
        uint256 tokenId = uint256(presentId);
        _mint(to, tokenId);
        
        return tokenId;
    }

    // --- 移除 getUnwrappedGiftInfo 函数 ---

    // --- 修改 generateTokenURI 以实时获取数据 ---
    function generateTokenURI(
        uint256 tokenId
    ) internal view returns (string memory) {
        IPresentViewU present = IPresentViewU(presentContract);
        bytes32 presentId = bytes32(tokenId);

        // 从 Present.sol 实时获取数据
        (address creator, string memory title, string memory description,,,,,) = present.getPresent(presentId);
        IPresentViewU.Asset[] memory assets = present.getPresentContent(presentId);
        address recipient = ownerOf(tokenId); // 接收者即为当前 NFT 的所有者
        
        uint256 ethValue = 0;
        bool hasTokenRewards = false;
        for (uint i = 0; i < assets.length; i++) {
            if (assets[i].tokens == address(0)) {
                ethValue += assets[i].amounts;
            } else {
                hasTokenRewards = true;
            }
        }
        
        string memory svg = generateUnwrappedSVG(tokenId, title, ethValue, hasTokenRewards);
        
        string memory attributes = string(
            abi.encodePacked(
                '[',
                    '{"trait_type": "Present ID", "value": "', tokenId.toString(), '"},',
                    '{"trait_type": "Type", "value": "Unwrapped"},',
                    '{"trait_type": "Original ETH Value", "value": "', (ethValue / 1e15).toString(), ' mETH"},', // 明确为原始总价值
                    '{"trait_type": "Creator", "value": "', Strings.toHexString(uint160(creator), 20), '"},',
                    '{"trait_type": "Recipient", "value": "', Strings.toHexString(uint160(recipient), 20), '"},',
                    '{"trait_type": "Has Token Rewards", "value": "', hasTokenRewards ? "Yes" : "No", '"}'
                ,']'
            )
        );
        
        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "', title, ' (Unwrapped)",',
                        '"description": "', description, ' This gift has been unwrapped and the contents have been claimed!",',
                        '"image": "data:image/svg+xml;base64,', Base64.encode(bytes(svg)), '",',
                        '"attributes": ', attributes,
                        '}'
                    )
                )
            )
        );
        
        return string(abi.encodePacked("data:application/json;base64,", json));
    }

    // --- 修改 generateUnwrappedSVG 的参数 ---
    function generateUnwrappedSVG(
        uint256 tokenId,
        string memory giftTitle,
        uint256 ethValue,
        bool hasTokenRewards
    ) internal pure returns (string memory) {
        string memory bgColor = ethValue >= 1e18 ? "#ff6b6b" : ethValue >= 1e16 ? "#ffa500" : "#ff69b4";
        string memory glowColor = ethValue >= 1e18 ? "#ffcccc" : "#ffe0b3";
        
        string memory displayTitle = bytes(giftTitle).length > 18 ? 
            string(abi.encodePacked(substring(giftTitle, 0, 15), "...")) : 
            giftTitle;
            
        string memory stars = generateStars(ethValue);
        
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
                'Original Value: ', (ethValue / 1e15).toString(), ' mETH',
                '</text>',
                hasTokenRewards ? 
                    '<text x="200" y="245" text-anchor="middle" font-family="Arial" font-size="10" fill="white">+ Token Rewards</text>' : 
                    '',
                '<text x="200" y="270" text-anchor="middle" font-family="Arial" font-size="10" fill="white" opacity="0.8">',
                'Token #', tokenId.toString(),
                '</text>',
                '</svg>'
            )
        );
    }
    
    function generateStars(uint256 ethValue) internal pure returns (string memory) {
        uint256 starCount = ethValue >= 1e18 ? 8 : ethValue >= 1e16 ? 5 : 3;
        string memory stars = "";
        
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
    
    function substring(string memory str, uint startIndex, uint endIndex) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex - startIndex);
        for (uint i = startIndex; i < endIndex; i++) {
            result[i - startIndex] = strBytes[i];
        }
        return string(result);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        require(_ownerOf(tokenId) != address(0), "Token does not exist");
        return generateTokenURI(tokenId);
    }
    
    // --- 修复 OpenZeppelin v5.0 的 override 要求 ---
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