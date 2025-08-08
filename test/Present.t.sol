// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console, Vm} from "forge-std/Test.sol";
import {Present} from "../src/Present.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockPresentNFT} from "./mocks/MockPresentNFT.sol";

contract PresentTest is Test {
    // 测试合约和模拟代币
    Present present;
    MockERC20 token1;
    MockERC20 token2;
    MockPresentNFT wrappedNFT;
    MockPresentNFT unwrappedNFT;
    
    // 测试账户
    address owner = address(0x1);
    address sender = address(0x2);
    address recipient1 = address(0x3);
    address recipient2 = address(0x4);
    address nonRecipient = address(0x5);
    address nonOwner = address(0x6);
    
    // 测试数据
    uint256 constant ETH_AMOUNT = 1 ether;
    uint256 constant TOKEN1_AMOUNT = 100 * 10**18;
    uint256 constant TOKEN2_AMOUNT = 50 * 10**18;
    
    // 事件哈希
    bytes32 constant WRAP_PRESENT_EVENT_SIG = 0xf57d75a06786ec46ba529c7c6a4a8c5f0c1eae07a3a01fa6c75da0320a9f7588;
    bytes32 constant UNWRAP_PRESENT_EVENT_SIG = 0x9de2336fa3890bbd478db2ada6f7a0d52e9441f9a861cc6e4e0a2286462f166e;
    bytes32 constant TAKE_BACK_EVENT_SIG = 0xf3209814a57a2e4e82032ce6d5fd40f3d9cf6d6df64ab77518090915d18df53c;
    bytes32 constant PRESENT_EXPIRED_EVENT_SIG = 0x1a0ebcb6227601a7f5e6a7c1383ceefc5207c3ab1c74cc99e43a9fbaeb474f96;
    
    // 设置测试环境
    function setUp() public {
        // 设置账户余额
        vm.deal(sender, 10 ether);
        vm.deal(owner, 1 ether);
        vm.deal(nonOwner, 1 ether);
        
        // 部署测试合约
        vm.prank(owner);
        present = new Present(owner);
        
        // 部署模拟代币
        token1 = new MockERC20("Test Token 1", "TT1", 18);
        token2 = new MockERC20("Test Token 2", "TT2", 18);
        
        // 部署NFT合约
        wrappedNFT = new MockPresentNFT("Wrapped Present", "WRAP");
        unwrappedNFT = new MockPresentNFT("Unwrapped Present", "UNWRAP");
        
        // 设置NFT合约地址
        vm.prank(owner);
        present.setNFTContracts(address(wrappedNFT), address(unwrappedNFT));
        
        // 给sender铸造测试代币
        token1.mint(sender, TOKEN1_AMOUNT * 2);
        token2.mint(sender, TOKEN2_AMOUNT * 2);
        
        // sender授权合约使用代币
        vm.startPrank(sender);
        token1.approve(address(present), type(uint256).max);
        token2.approve(address(present), type(uint256).max);
        vm.stopPrank();
        
        // 设置NFT合约的Present地址
        wrappedNFT.setPresentContract(address(present));
        unwrappedNFT.setPresentContract(address(present));
    }
    
    // 测试创建ETH礼物
    function test_WrapETHPresent() public {
        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        
        Present.Asset[] memory assets = new Present.Asset[](1);
        assets[0] = Present.Asset(address(0), ETH_AMOUNT);
        
        vm.recordLogs();
        vm.prank(sender);
        present.wrapPresent{value: ETH_AMOUNT}(recipients, assets);
        
        // 从事件中获取礼物ID (不使用变量避免警告)
        getPresentIdFromEvents();
        
        // 验证合约余额
        assertEq(address(present).balance, ETH_AMOUNT, "Contract should hold ETH");
        
        // 验证统计信息
        assertEq(present.totalPresentsWrapped(), 1, "Total presents wrapped should be 1");
        assertEq(present.userWrappedCount(sender), 1, "User wrapped count should be 1");
        
        // 验证NFT铸造
        assertEq(wrappedNFT.balanceOf(sender), 1, "Sender should have wrapped NFT");
    }
    
    // 测试创建ERC20代币礼物
    function test_WrapTokenPresent() public {
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        
        Present.Asset[] memory assets = new Present.Asset[](2);
        assets[0] = Present.Asset(address(token1), TOKEN1_AMOUNT);
        assets[1] = Present.Asset(address(token2), TOKEN2_AMOUNT);
        
        uint256 senderToken1Before = token1.balanceOf(sender);
        uint256 senderToken2Before = token2.balanceOf(sender);
        
        vm.recordLogs();
        vm.prank(sender);
        present.wrapPresent(recipients, assets);
        
        // 从事件中获取礼物ID (不使用变量避免警告)
        getPresentIdFromEvents();
        
        // 验证代币转移
        assertEq(token1.balanceOf(sender), senderToken1Before - TOKEN1_AMOUNT, "Sender token1 should decrease");
        assertEq(token2.balanceOf(sender), senderToken2Before - TOKEN2_AMOUNT, "Sender token2 should decrease");
        assertEq(token1.balanceOf(address(present)), TOKEN1_AMOUNT, "Contract should hold token1");
        assertEq(token2.balanceOf(address(present)), TOKEN2_AMOUNT, "Contract should hold token2");
    }
    
    // 测试创建混合礼物（ETH + 代币）
    function test_WrapMixedPresent() public {
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        
        Present.Asset[] memory assets = new Present.Asset[](3);
        assets[0] = Present.Asset(address(0), ETH_AMOUNT);
        assets[1] = Present.Asset(address(token1), TOKEN1_AMOUNT);
        assets[2] = Present.Asset(address(token2), TOKEN2_AMOUNT);
        
        vm.recordLogs();
        vm.prank(sender);
        present.wrapPresent{value: ETH_AMOUNT}(recipients, assets);
        
        // 从事件中获取礼物ID
        bytes32 presentId = getPresentIdFromEvents();
        
        // 验证存储的礼物内容
        Present.Asset[] memory storedAssets = present.getPresentContent(presentId);
        
        assertEq(storedAssets.length, 3, "Should store 3 assets");
        assertEq(storedAssets[0].tokens, address(0), "First asset should be ETH");
        assertEq(storedAssets[0].amounts, ETH_AMOUNT, "ETH amount should match");
        assertEq(storedAssets[1].tokens, address(token1), "Second asset should be token1");
        assertEq(storedAssets[1].amounts, TOKEN1_AMOUNT, "Token1 amount should match");
    }
    
    // 测试拆开礼物
    function test_UnwrapPresent() public {
        // 先创建礼物
        bytes32 presentId = createMixedPresent();
        
        uint256 recipient1EthBefore = recipient1.balance;
        uint256 recipient1Token1Before = token1.balanceOf(recipient1);
        uint256 recipient1Token2Before = token2.balanceOf(recipient1);
        
        // 拆开礼物
        vm.prank(recipient1);
        present.unwrapPresent(presentId);
        
        // 验证资产转移
        assertEq(recipient1.balance, recipient1EthBefore + ETH_AMOUNT, "Recipient should receive ETH");
        assertEq(token1.balanceOf(recipient1), recipient1Token1Before + TOKEN1_AMOUNT, "Recipient should receive token1");
        assertEq(token2.balanceOf(recipient1), recipient1Token2Before + TOKEN2_AMOUNT, "Recipient should receive token2");
        
        // 验证礼物状态
        assertEq(uint8(present.getPresentStatus(presentId)), 1, "Present should be unwrapped");
        
        // 验证统计信息
        assertEq(present.totalPresentsUnwrapped(), 1, "Total presents unwrapped should be 1");
        assertEq(present.userUnwrappedCount(recipient1), 1, "User unwrapped count should be 1");
        
        // 验证NFT铸造
        assertEq(unwrappedNFT.balanceOf(recipient1), 1, "Recipient should have unwrapped NFT");
    }
    
    // 测试未授权拆开礼物
    function test_UnwrapPresent_Unauthorized() public {
        // 先创建礼物
        bytes32 presentId = createMixedPresent();
        
        // 非接收者尝试拆开
        vm.prank(nonRecipient);
        vm.expectRevert("Only recipient can unwrap this present");
        present.unwrapPresent(presentId);
    }
    
    // 测试已拆开礼物不能再次拆开
    function test_UnwrapPresent_AlreadyUnwrapped() public {
        // 先创建礼物
        bytes32 presentId = createMixedPresent();
        
        // 第一次拆开礼物
        vm.prank(recipient1);
        present.unwrapPresent(presentId);
        
        // 尝试第二次拆开
        vm.prank(recipient1);
        vm.expectRevert("Present cannot be unwrapped");
        present.unwrapPresent(presentId);
    }
    
    // 测试收回礼物
    function test_TakeBack() public {
        // 先创建礼物
        bytes32 presentId = createMixedPresent();
        
        uint256 senderEthBefore = sender.balance;
        uint256 senderToken1Before = token1.balanceOf(sender);
        uint256 senderToken2Before = token2.balanceOf(sender);
        
        // 收回礼物
        vm.prank(sender);
        present.takeBack(presentId);
        
        // 验证资产转移
        assertEq(sender.balance, senderEthBefore + ETH_AMOUNT, "Sender should receive ETH back");
        assertEq(token1.balanceOf(sender), senderToken1Before + TOKEN1_AMOUNT, "Sender should receive token1 back");
        assertEq(token2.balanceOf(sender), senderToken2Before + TOKEN2_AMOUNT, "Sender should receive token2 back");
        
        // 验证礼物状态
        assertEq(uint8(present.getPresentStatus(presentId)), 2, "Present should be taken back");
        
        // 验证统计信息
        assertEq(present.totalPresentsTakenBack(), 1, "Total presents taken back should be 1");
    }
    
    // 测试未授权收回礼物
    function test_TakeBack_Unauthorized() public {
        // 先创建礼物
        bytes32 presentId = createMixedPresent();
        
        // 非发送者尝试收回
        vm.prank(nonRecipient);
        vm.expectRevert("Only sender can call this function");
        present.takeBack(presentId);
    }
    
    // 测试已拆开的礼物不能被收回
    function test_TakeBack_AlreadyUnwrapped() public {
        // 先创建礼物
        bytes32 presentId = createMixedPresent();
        
        // 拆开礼物
        vm.prank(recipient1);
        present.unwrapPresent(presentId);
        
        // 尝试收回已拆开的礼物
        vm.prank(sender);
        vm.expectRevert("Cannot take back: gift is unwrapped or not expired");
        present.takeBack(presentId);
    }
    
    // 测试已收回的礼物不能再次收回
    function test_TakeBack_AlreadyTakenBack() public {
        // 先创建礼物
        bytes32 presentId = createMixedPresent();
        
        // 第一次收回礼物
        vm.prank(sender);
        present.takeBack(presentId);
        
        // 尝试第二次收回
        vm.prank(sender);
        vm.expectRevert();  // 使用通用expectRevert而不指定具体消息
        present.takeBack(presentId);
    }
    
    // 测试礼物过期
    function test_PresentExpiry() public {
        // 先创建礼物
        bytes32 presentId = createMixedPresent();
        
        // 快进时间到过期后
        vm.warp(block.timestamp + present.defaultExpiryPeriod() + 1);
        
        // 验证礼物已过期
        assertTrue(present.isExpired(presentId), "Present should be expired");
        
        // 接收者尝试拆开过期礼物
        vm.prank(recipient1);
        vm.expectRevert("Present has expired");
        present.unwrapPresent(presentId);
        
        // 发送者可以收回过期礼物
        vm.prank(sender);
        present.takeBack(presentId);
        
        assertEq(uint8(present.getPresentStatus(presentId)), 2, "Present should be taken back");
    }
    
    // 测试代币黑名单功能
    function test_TokenBlacklist() public {
        // 所有者将token1加入黑名单
        vm.prank(owner);
        present.setTokenBlacklist(address(token1), true);
        
        // 尝试创建包含黑名单代币的礼物
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        
        Present.Asset[] memory assets = new Present.Asset[](1);
        assets[0] = Present.Asset(address(token1), TOKEN1_AMOUNT);
        
        // 应该失败
        vm.prank(sender);
        vm.expectRevert("Contains blacklisted token");
        present.wrapPresent(recipients, assets);
    }
    
    // 测试无法将ETH加入黑名单
    function test_CannotBlacklistETH() public {
        // 尝试将ETH加入黑名单
        vm.prank(owner);
        vm.expectRevert("Cannot blacklist ETH");
        present.setTokenBlacklist(address(0), true);
    }
    
    // 测试非所有者无法设置黑名单
    function test_TokenBlacklist_Unauthorized() public {
        // 非所有者尝试将token1加入黑名单
        vm.prank(nonOwner);
        vm.expectRevert();  // 使用通用expectRevert而不指定具体消息
        present.setTokenBlacklist(address(token1), true);
    }
    
    // 测试合约暂停功能
    function test_Pause() public {
        // 所有者暂停合约
        vm.prank(owner);
        present.pause();
        
        // 尝试创建礼物应该失败
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        
        Present.Asset[] memory assets = new Present.Asset[](1);
        assets[0] = Present.Asset(address(token1), TOKEN1_AMOUNT);
        
        vm.prank(sender);
        vm.expectRevert();  // 使用通用expectRevert而不指定具体消息
        present.wrapPresent(recipients, assets);
        
        // 恢复合约
        vm.prank(owner);
        present.unpause();
        
        // 现在应该可以创建礼物
        vm.prank(sender);
        present.wrapPresent(recipients, assets);
    }
    
    // 测试非所有者不能暂停合约
    function test_Pause_Unauthorized() public {
        vm.prank(nonOwner);
        vm.expectRevert();  // 使用通用expectRevert而不指定具体消息
        present.pause();
    }
    
    // 测试非所有者不能解除暂停
    function test_Unpause_Unauthorized() public {
        // 所有者暂停合约
        vm.prank(owner);
        present.pause();
        
        // 非所有者尝试解除暂停
        vm.prank(nonOwner);
        vm.expectRevert();  // 使用通用expectRevert而不指定具体消息
        present.unpause();
    }
    
    // 测试紧急提取功能
    function test_EmergencyWithdraw() public {
        // 向合约直接发送ETH
        vm.deal(address(present), 2 ether);
        
        uint256 ownerEthBefore = owner.balance;
        
        // 所有者进行紧急提取
        vm.prank(owner);
        present.emergencyWithdraw(address(0), 1 ether);
        
        assertEq(owner.balance, ownerEthBefore + 1 ether, "Owner should receive ETH");
        assertEq(address(present).balance, 1 ether, "Contract balance should decrease");
    }
    
    // 测试紧急提取代币
    function test_EmergencyWithdraw_Token() public {
        // 直接向合约发送代币
        token1.mint(address(present), TOKEN1_AMOUNT);
        
        uint256 ownerTokenBefore = token1.balanceOf(owner);
        
        // 所有者提取代币
        vm.prank(owner);
        present.emergencyWithdraw(address(token1), TOKEN1_AMOUNT);
        
        assertEq(token1.balanceOf(owner), ownerTokenBefore + TOKEN1_AMOUNT, "Owner should receive tokens");
        assertEq(token1.balanceOf(address(present)), 0, "Contract should have no tokens left");
    }
    
    // 测试非所有者不能紧急提取
    function test_EmergencyWithdraw_Unauthorized() public {
        vm.deal(address(present), 1 ether);
        
        vm.prank(nonOwner);
        vm.expectRevert();  // 使用通用expectRevert而不指定具体消息
        present.emergencyWithdraw(address(0), 1 ether);
    }
    
    // 测试提取超过余额
    function test_EmergencyWithdraw_InsufficientBalance() public {
        vm.deal(address(present), 1 ether);
        
        vm.prank(owner);
        vm.expectRevert("Insufficient ETH balance");
        present.emergencyWithdraw(address(0), 2 ether);
    }
    
    // 测试配置更新
    function test_UpdateConfig() public {
        vm.prank(owner);
        present.updateConfig(30, 150, 180 days);
        
        assertEq(present.maxAssetCount(), 30, "maxAssetCount should be updated");
        assertEq(present.maxRecipientCount(), 150, "maxRecipientCount should be updated");
        assertEq(present.defaultExpiryPeriod(), 180 days, "defaultExpiryPeriod should be updated");
    }
    
    // 测试非所有者不能更新配置
    function test_UpdateConfig_Unauthorized() public {
        vm.prank(nonOwner);
        vm.expectRevert();  // 使用通用expectRevert而不指定具体消息
        present.updateConfig(30, 150, 180 days);
    }
    
    // 测试边界条件：太多资产
    function test_TooManyAssets() public {
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        
        // 创建超过限制的资产
        uint256 maxAssetCount = present.maxAssetCount();
        Present.Asset[] memory assets = new Present.Asset[](maxAssetCount + 1);
        
        for (uint256 i = 0; i < assets.length; i++) {
            assets[i] = Present.Asset(address(token1), 1);
        }
        
        // 应该失败
        vm.prank(sender);
        vm.expectRevert("Invalid content size");
        present.wrapPresent(recipients, assets);
    }
    
    // 测试边界条件：太多接收者
    function test_TooManyRecipients() public {
        // 创建超过限制的接收者列表
        uint256 maxRecipientCount = present.maxRecipientCount();
        address[] memory recipients = new address[](maxRecipientCount + 1);
        
        for (uint256 i = 0; i < recipients.length; i++) {
            recipients[i] = address(uint160(i + 100));
        }
        
        Present.Asset[] memory assets = new Present.Asset[](1);
        assets[0] = Present.Asset(address(token1), TOKEN1_AMOUNT);
        
        vm.prank(sender);
        vm.expectRevert("Too many recipients");
        present.wrapPresent(recipients, assets);
    }
    
    // 测试零金额礼物
    function test_ZeroAmount() public {
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        
        Present.Asset[] memory assets = new Present.Asset[](1);
        assets[0] = Present.Asset(address(token1), 0);
        
        vm.prank(sender);
        vm.expectRevert("Amount must be positive");
        present.wrapPresent(recipients, assets);
    }
    
    // 测试任何人可领取礼物
    function test_AnyoneCanUnwrap() public {
        // 创建任何人可领取的礼物
        address[] memory recipients = new address[](0); // 空数组表示任何人可领取
        
        Present.Asset[] memory assets = new Present.Asset[](1);
        assets[0] = Present.Asset(address(token1), TOKEN1_AMOUNT);
        
        vm.recordLogs();
        vm.prank(sender);
        present.wrapPresent(recipients, assets);
        
        bytes32 presentId = getPresentIdFromEvents();
        
        // 非指定接收者也可以领取
        vm.prank(nonRecipient);
        present.unwrapPresent(presentId);
        
        assertEq(token1.balanceOf(nonRecipient), TOKEN1_AMOUNT, "Non-recipient should receive tokens");
    }
    
    // 测试ETH不足情况
    function test_InsufficientETH() public {
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        
        Present.Asset[] memory assets = new Present.Asset[](1);
        assets[0] = Present.Asset(address(0), ETH_AMOUNT);
        
        vm.prank(sender);
        vm.expectRevert("Insufficient ETH sent");
        present.wrapPresent{value: ETH_AMOUNT - 1}(recipients, assets);
    }
    
    // 测试多余ETH退还功能
    function test_ETHRefund() public {
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        
        Present.Asset[] memory assets = new Present.Asset[](1);
        assets[0] = Present.Asset(address(0), ETH_AMOUNT);
        
        uint256 senderEthBefore = sender.balance;
        
        vm.prank(sender);
        present.wrapPresent{value: ETH_AMOUNT + 1 ether}(recipients, assets);
        
        assertEq(sender.balance, senderEthBefore - ETH_AMOUNT, "Excess ETH should be refunded");
        assertEq(address(present).balance, ETH_AMOUNT, "Contract should keep exact ETH amount");
    }
    
    // 测试强制过期礼物功能
    function test_ForceExpirePresent() public {
        // 先创建礼物
        bytes32 presentId = createMixedPresent();
        
        // 所有者强制使礼物过期
        vm.prank(owner);
        present.forceExpirePresent(presentId);
        
        // 检查礼物状态
        assertEq(uint8(present.getPresentStatus(presentId)), 3, "Present should be expired");
        
        // 接收者尝试拆开过期礼物
        vm.prank(recipient1);
        vm.expectRevert("Present cannot be unwrapped");
        present.unwrapPresent(presentId);
    }
    
    // 测试非所有者不能强制过期礼物
    function test_ForceExpirePresent_Unauthorized() public {
        // 先创建礼物
        bytes32 presentId = createMixedPresent();
        
        // 非所有者尝试强制使礼物过期
        vm.prank(nonOwner);
        vm.expectRevert();  // 使用通用expectRevert而不指定具体消息
        present.forceExpirePresent(presentId);
    }
    
    // 测试无法强制过期不存在的礼物
    function test_ForceExpirePresent_NonExistent() public {
        bytes32 nonExistentPresentId = bytes32(uint256(123));
        
        // 尝试强制过期不存在的礼物
        vm.prank(owner);
        vm.expectRevert("Present does not exist");
        present.forceExpirePresent(nonExistentPresentId);
    }
    
    // 测试无法强制过期已拆开的礼物
    function test_ForceExpirePresent_AlreadyUnwrapped() public {
        // 先创建礼物
        bytes32 presentId = createMixedPresent();
        
        // 拆开礼物
        vm.prank(recipient1);
        present.unwrapPresent(presentId);
        
        // 尝试强制过期已拆开的礼物
        vm.prank(owner);
        vm.expectRevert("Present not active");
        present.forceExpirePresent(presentId);
    }
    
    // 测试ERC721接收功能
    function test_OnERC721Received() public {
        bytes4 expectedSelector = bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
        bytes4 returnedSelector = present.onERC721Received(address(0), address(0), 0, "");
        assertEq(returnedSelector, expectedSelector, "Should return correct selector");
    }
    
    // 测试设置NFT合约地址
    function test_SetNFTContracts() public {
        // 部署新的测试合约
        vm.prank(owner);
        Present newPresent = new Present(owner);
        
        address mockWrappedNFT = address(0x123);
        address mockUnwrappedNFT = address(0x456);
        
        // 设置NFT合约地址
        vm.prank(owner);
        newPresent.setNFTContracts(mockWrappedNFT, mockUnwrappedNFT);
        
        assertEq(newPresent.wrappedNFT(), mockWrappedNFT, "Wrapped NFT address should be set");
        assertEq(newPresent.unwrappedNFT(), mockUnwrappedNFT, "Unwrapped NFT address should be set");
    }
    
    // 测试非所有者不能设置NFT合约地址
    function test_SetNFTContracts_Unauthorized() public {
        address mockWrappedNFT = address(0x123);
        address mockUnwrappedNFT = address(0x456);
        
        vm.prank(nonOwner);
        vm.expectRevert();  // 使用通用expectRevert而不指定具体消息
        present.setNFTContracts(mockWrappedNFT, mockUnwrappedNFT);
    }
    
    // 测试没有设置NFT合约的情况下打包礼物
    function test_WrapPresent_NoNFTContract() public {
        // 部署新的测试合约（不设置NFT地址）
        vm.prank(owner);
        Present newPresent = new Present(owner);
        
        address[] memory recipients = new address[](1);
        recipients[0] = recipient1;
        
        Present.Asset[] memory assets = new Present.Asset[](1);
        assets[0] = Present.Asset(address(token1), TOKEN1_AMOUNT);
        
        // 授权新合约
        vm.prank(sender);
        token1.approve(address(newPresent), TOKEN1_AMOUNT);
        
        // 应该可以正常打包礼物，即使没有设置NFT合约
        vm.prank(sender);
        newPresent.wrapPresent(recipients, assets);
    }
    
    // 内部辅助函数：创建混合礼物
    function createMixedPresent() internal returns (bytes32) {
        address[] memory recipients = new address[](2);
        recipients[0] = recipient1;
        recipients[1] = recipient2;
        
        Present.Asset[] memory assets = new Present.Asset[](3);
        assets[0] = Present.Asset(address(0), ETH_AMOUNT);
        assets[1] = Present.Asset(address(token1), TOKEN1_AMOUNT);
        assets[2] = Present.Asset(address(token2), TOKEN2_AMOUNT);
        
        vm.recordLogs();
        vm.prank(sender);
        present.wrapPresent{value: ETH_AMOUNT}(recipients, assets);
        
        return getPresentIdFromEvents();
    }
    
    // 从事件日志中获取礼物ID
    function getPresentIdFromEvents() internal returns (bytes32) {
        Vm.Log[] memory entries = vm.getRecordedLogs();
        
        // 查找WrapPresent事件
        // 事件签名: keccak256("WrapPresent(bytes32,address)")
        bytes32 wrapEventSignature = WRAP_PRESENT_EVENT_SIG;
        
        for (uint i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == wrapEventSignature) {
                // 第一个索引参数是presentId
                return bytes32(entries[i].topics[1]);
            }
        }
        
        revert("WrapPresent event not found");
    }
} 