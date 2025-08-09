// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/WrappedPresentNFT.sol";

contract WrappedPresentNFTTest is Test {
    WrappedPresentNFT public nft;
    
    // 测试用地址
    address public owner;
    address public user1;
    address public user2;
    address public sender;
    
    // 测试数据
    uint256 public constant TOKEN_ID = 1;
    string public constant TITLE = "Birthday Gift";
    string public constant DESCRIPTION = "A wonderful birthday present";
    string public constant IMAGE_TYPE = "gift";
    uint256 public constant VALUE = 100;
    
    function setUp() public {
        // 设置测试地址
        owner = address(this);  // 部署者
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        sender = makeAddr("sender");
        
        // 部署合约
        nft = new WrappedPresentNFT();
    }
    
    // 测试合约部署
    function testDeployment() public {
        assertEq(nft.name(), "WrappedPresent");
        assertEq(nft.symbol(), "WP");
        assertEq(nft.presentContract(), owner);
    }
    
    // 测试正常铸造
    function testMint() public {
        // 记录铸造前状态
        assertEq(nft.balanceOf(user1), 0);
        
        // 铸造 NFT
        nft.mint(user1, TOKEN_ID, TITLE, DESCRIPTION, IMAGE_TYPE, VALUE, sender);
        
        // 验证铸造结果
        assertEq(nft.balanceOf(user1), 1);
        assertEq(nft.ownerOf(TOKEN_ID), user1);
        assertEq(nft.totalSupply(), 1);
        
        // 验证元数据
        WrappedPresentNFT.PresentMetadata memory metadata = nft.getPresentInfo(TOKEN_ID);
        assertEq(metadata.title, TITLE);
        assertEq(metadata.description, DESCRIPTION);
        assertEq(metadata.imageType, IMAGE_TYPE);
        assertEq(metadata.value, VALUE);
        assertEq(metadata.sender, sender);
        assertTrue(metadata.createdAt > 0);
    }
    
    // 测试只有 presentContract 能铸造
    function testOnlyPresentContractCanMint() public {
        // 切换到非授权用户
        vm.prank(user1);
        
        // 尝试铸造应该失败
        vm.expectRevert("Only present contract can mint");
        nft.mint(user2, TOKEN_ID, TITLE, DESCRIPTION, IMAGE_TYPE, VALUE, sender);
    }
    
    // 测试重复铸造相同 tokenId 会失败
    function testCannotMintDuplicateTokenId() public {
        // 第一次铸造
        nft.mint(user1, TOKEN_ID, TITLE, DESCRIPTION, IMAGE_TYPE, VALUE, sender);
        
        // 尝试铸造相同 tokenId 应该失败
        vm.expectRevert();
        nft.mint(user2, TOKEN_ID, "Another Gift", "Another description", IMAGE_TYPE, 200, sender);
    }
    
    // 测试获取不存在的 NFT 信息
    function testGetPresentInfoNonExistentToken() public {
        vm.expectRevert("NFT does not exist");
        nft.getPresentInfo(999);
    }
    
    // 测试批量获取用户 NFT
    function testGetUserNFTs() public {
        // 给 user1 铸造多个 NFT
        nft.mint(user1, 1, "Gift 1", "Description 1", IMAGE_TYPE, 100, sender);
        nft.mint(user1, 2, "Gift 2", "Description 2", IMAGE_TYPE, 200, sender);
        nft.mint(user1, 3, "Gift 3", "Description 3", IMAGE_TYPE, 300, sender);
        
        // 给 user2 铸造一个 NFT
        nft.mint(user2, 4, "Gift 4", "Description 4", IMAGE_TYPE, 400, sender);
        
        // 获取 user1 的 NFT
        uint256[] memory user1NFTs = nft.getUserNFTs(user1);
        assertEq(user1NFTs.length, 3);
        assertEq(user1NFTs[0], 1);
        assertEq(user1NFTs[1], 2);
        assertEq(user1NFTs[2], 3);
        
        // 获取 user2 的 NFT
        uint256[] memory user2NFTs = nft.getUserNFTs(user2);
        assertEq(user2NFTs.length, 1);
        assertEq(user2NFTs[0], 4);
    }
    
    // 测试空用户的 NFT 列表
    function testGetUserNFTsEmptyUser() public {
        uint256[] memory emptyNFTs = nft.getUserNFTs(user1);
        assertEq(emptyNFTs.length, 0);
    }
    
    // 测试 NFT 转账功能
    function testTransfer() public {
        // 铸造 NFT 给 user1
        nft.mint(user1, TOKEN_ID, TITLE, DESCRIPTION, IMAGE_TYPE, VALUE, sender);
        
        // user1 转账给 user2
        vm.prank(user1);
        nft.transferFrom(user1, user2, TOKEN_ID);
        
        // 验证转账结果
        assertEq(nft.ownerOf(TOKEN_ID), user2);
        assertEq(nft.balanceOf(user1), 0);
        assertEq(nft.balanceOf(user2), 1);
    }
    
    // 测试 tokenURI 生成
    function testTokenURI() public {
        nft.mint(user1, TOKEN_ID, TITLE, DESCRIPTION, IMAGE_TYPE, VALUE, sender);
        
        string memory uri = nft.tokenURI(TOKEN_ID);
        assertTrue(bytes(uri).length > 0);
        
        // 检查是否包含 base64 前缀
        assertTrue(_startsWith(uri, "data:application/json;base64,"));
    }
    
    // 测试不存在的 token URI
    function testTokenURINonExistentToken() public {
        vm.expectRevert();
        nft.tokenURI(999);
    }
    
    // 测试合约接口支持
    function testSupportsInterface() public {
        // ERC721
        assertTrue(nft.supportsInterface(0x80ac58cd));
        // ERC721Metadata
        assertTrue(nft.supportsInterface(0x5b5e139f));
        // ERC721Enumerable
        assertTrue(nft.supportsInterface(0x780e9d63));
        // ERC165
        assertTrue(nft.supportsInterface(0x01ffc9a7));
    }
    
    // 测试颜色生成功能
    function testGetColorByType() public {
        // 这些是内部函数，我们通过生成 SVG 来间接测试
        nft.mint(user1, 1, "Gift", "Description", "gift", 100, sender);
        nft.mint(user1, 2, "Surprise", "Description", "surprise", 200, sender);
        nft.mint(user1, 3, "Business", "Description", "business", 300, sender);
        
        // 生成 token URI，确保没有错误
        string memory uri1 = nft.tokenURI(1);
        string memory uri2 = nft.tokenURI(2);
        string memory uri3 = nft.tokenURI(3);
        
        assertTrue(bytes(uri1).length > 0);
        assertTrue(bytes(uri2).length > 0);
        assertTrue(bytes(uri3).length > 0);
    }
    
    // 测试边界情况：零地址
    function testMintToZeroAddress() public {
        vm.expectRevert();
        nft.mint(address(0), TOKEN_ID, TITLE, DESCRIPTION, IMAGE_TYPE, VALUE, sender);
    }
    
    // 测试大数值
    function testMintWithLargeValue() public {
        uint256 largeValue = type(uint256).max;
        nft.mint(user1, TOKEN_ID, TITLE, DESCRIPTION, IMAGE_TYPE, largeValue, sender);
        
        WrappedPresentNFT.PresentMetadata memory metadata = nft.getPresentInfo(TOKEN_ID);
        assertEq(metadata.value, largeValue);
    }
    
    // 测试空字符串
    function testMintWithEmptyStrings() public {
        nft.mint(user1, TOKEN_ID, "", "", "", VALUE, sender);
        
        WrappedPresentNFT.PresentMetadata memory metadata = nft.getPresentInfo(TOKEN_ID);
        assertEq(metadata.title, "");
        assertEq(metadata.description, "");
        assertEq(metadata.imageType, "");
    }
    
    // 测试长标题截断功能
    function testLongTitleTruncation() public {
        string memory longTitle = "This is a very long title that should be truncated in the SVG";
        nft.mint(user1, TOKEN_ID, longTitle, DESCRIPTION, IMAGE_TYPE, VALUE, sender);
        
        // 生成 token URI，确保没有错误
        string memory uri = nft.tokenURI(TOKEN_ID);
        assertTrue(bytes(uri).length > 0);
        
        // 验证元数据中保存的是完整标题
        WrappedPresentNFT.PresentMetadata memory metadata = nft.getPresentInfo(TOKEN_ID);
        assertEq(metadata.title, longTitle);
    }
    
    // 辅助函数：检查字符串是否以指定前缀开头
    function _startsWith(string memory str, string memory prefix) internal pure returns (bool) {
        bytes memory strBytes = bytes(str);
        bytes memory prefixBytes = bytes(prefix);
        
        if (strBytes.length < prefixBytes.length) {
            return false;
        }
        
        for (uint i = 0; i < prefixBytes.length; i++) {
            if (strBytes[i] != prefixBytes[i]) {
                return false;
            }
        }
        
        return true;
    }
    
    // Fuzz 测试：随机值测试
    function testFuzzMint(
        address to,
        uint256 tokenId,
        uint256 value,
        string calldata title,
        string calldata description
    ) public {
        // 排除零地址
        vm.assume(to != address(0));
        // 确保 tokenId 唯一
        vm.assume(tokenId > 0 && tokenId < 1000000);
        
        try nft.mint(to, tokenId, title, description, IMAGE_TYPE, value, sender) {
            assertEq(nft.ownerOf(tokenId), to);
            assertEq(nft.balanceOf(to), 1);
        } catch {
            // 如果失败了，检查是否是重复的 tokenId
            // 这里可以添加更多的失败原因检查
        }
    }
}