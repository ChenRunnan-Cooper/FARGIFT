// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
//NFT合约
contract WrappedPresentNFT is ERC721 {
    address public presentContract;
    
    constructor() ERC721("WrappedPresent", "WP") {
        presentContract = msg.sender;  // 记录部署者（PresentContract）
    }
    
    function mint(address to, uint256 tokenId) external {
        require(msg.sender == presentContract, "Only present contract can mint");
        _mint(to, tokenId);  // 调用ERC721的内部_mint函数
    }
}

contract UnwrappedPresentNFT is ERC721 {
    address public presentContract;
    
    constructor() ERC721("UnwrappedPresent", "UP") {
        presentContract = msg.sender;
    }
    
    function mint(address to, uint256 tokenId) external {
        require(msg.sender == presentContract, "Only present contract can mint");
        _mint(to, tokenId);
    }
}

contract PresentContract is Ownable {
    // 礼物资产结构
    struct Asset {
        address token;
        uint256 amount;
    }

    // 礼物目前状态结构，详细信息，8.9新增title和description
    struct Present {
        address sender;
        address[] recipients;
        Asset[] assets;
        string title;         
        string description;   
        bool isUnwrapped;
        bool isTakenBack;
    }
    //打包，拆包，取回事件
    event WrapPresentTest(bytes32 indexed presentId, address sender);
    event UnwrapPresentTest(bytes32 indexed presentId, address taker);
    event TakeBackTest(bytes32 indexed presentId, address sender);

    // presents id值对应的Present状态，
    mapping(bytes32 => Present) private presents;
    //mapping(bytes32 => string) private titleOf;titleof和descriptionOf对应礼物的标题和描述,但我看应该放在Present结构体里面，让用户直接查
    //mapping(bytes32 => string) private descriptionOf;
    //mapping(bytes32 => mapping(address => uint256)) private presentTokenBalances;//用于追踪不同礼物里不同代币资产的具体数额  


     WrappedPresentNFT public wrappedPresentNFT;
     UnwrappedPresentNFT public unwrappedPresentNFT;


   constructor() Ownable(msg.sender) {
    wrappedPresentNFT = new WrappedPresentNFT();
    unwrappedPresentNFT = new UnwrappedPresentNFT();
}
    // 打包礼物：recipients代表接收者名单，assets代表的Asset结构上文已有，calldata用于节省gas，8.9按要求增加title和desc字段
    function wrapPresentTest(address[] calldata recipients,string calldata title, string calldata desc, Asset[] calldata assets) external payable {
        // 生成礼物ID
        bytes32 presentId = keccak256(abi.encodePacked(msg.sender, blockhash(block.number)));

        // 处理ETH
        if (msg.value > 0) {
           presentETH[presentId] = msg.value;
        }

        // 处理ERC20和ERC721资产，从msg.sender发送到当前合约地址，代码有安全漏洞之后再说吧
         for (uint256 i = 0; i < assets.length; i++) {
            Asset memory asset = assets[i];
            if (asset.token == address(0)) continue;

         
        try IERC165(asset.token).supportsInterface(type(IERC721).interfaceId) returns (bool isERC721) {
            if (isERC721) {
                // ERC721 transferFrom 没有返回值，直接调用
                IERC721(asset.token).transferFrom(msg.sender, address(this), asset.amount);
            } else {
                // ERC20 transferFrom 返回 bool
                require(IERC20(asset.token).transferFrom(msg.sender, address(this), asset.amount), "ERC20 transfer failed");
            }
        } catch {
            // 默认按 ERC20 处理
            require(IERC20(asset.token).transferFrom(msg.sender, address(this), asset.amount), "ERC20 transfer failed");
        }
    }

        // 存储礼物信息(26行)
        presents[presentId] = Present({
            sender: msg.sender,
            recipients: recipients,
            assets: assets,
            title: title,           
            description: desc,
            isUnwrapped: false,
            isTakenBack: false
        });
        

        // 给sender铸造Wrapped Present NFT
        wrappedPresentNFT.mint(msg.sender, uint256(presentId));

        emit WrapPresentTest(presentId, msg.sender);
    }

    // 拆开礼物

    mapping(bytes32 => uint256) private presentETH;

    function unwrapPresentTest(bytes32 presentId) external {
        Present storage present = presents[presentId];
        require(present.sender != address(0), "Present not exist");
        require(!present.isUnwrapped, "Present already unwrapped");
        require(!present.isTakenBack, "Present already taken back");

        // 检查调用者是否是recipient之一
        bool isRecipient = false;
        for (uint256 i = 0; i < present.recipients.length; i++) {
            if (present.recipients[i] == msg.sender) {
                isRecipient = true;
                break;
            }
        }
        require(isRecipient, "Not a recipient");

        // 标记为已拆开
        present.isUnwrapped = true;

        // 转移ETH
         uint256 ethAmount = presentETH[presentId];
         if (ethAmount > 0) {
         presentETH[presentId] = 0;
         (bool success, ) = msg.sender.call{value: ethAmount}("");
         require(success, "ETH transfer failed");
    }

        // 转移ERC20和ERC721资产
         for (uint256 i = 0; i < present.assets.length; i++) {
            Asset memory asset = present.assets[i];
            if (asset.token == address(0)) continue;

          try IERC165(asset.token).supportsInterface(type(IERC721).interfaceId) returns (bool isERC721) {
            if (isERC721) {
                // ERC721 transferFrom 没有返回值
                IERC721(asset.token).transferFrom(address(this), msg.sender, asset.amount);
            } else {
                // ERC20 transfer 返回 bool
                require(IERC20(asset.token).transfer(msg.sender, asset.amount), "ERC20 transfer failed");
            }
        } catch {
            // 默认按 ERC20 处理
            require(IERC20(asset.token).transfer(msg.sender, asset.amount), "ERC20 transfer failed");
        }
    }

        // 给调用者铸造Unwrapped Present NFT
        unwrappedPresentNFT.mint(msg.sender, uint256(presentId));

        emit UnwrapPresentTest(presentId, msg.sender);
    }

    // 收回礼物
    function takeBackTest(bytes32 presentId) external {
        Present storage present = presents[presentId];
        require(present.sender != address(0), "Present not exist");
        require(!present.isUnwrapped, "Present already unwrapped");
        require(!present.isTakenBack, "Present already taken back");
        require(msg.sender == present.sender, "Only sender can take back");

        // 标记为已收回
        present.isTakenBack = true;

        // 转移ETH回sender
        uint256 ethAmount = presentETH[presentId];
        if (ethAmount > 0) {
        presentETH[presentId] = 0;
        (bool success, ) = present.sender.call{value: ethAmount}("");
        require(success, "ETH transfer failed");
    }

        // 转移ERC20和ERC721资产回sender
        for (uint256 i = 0; i < present.assets.length; i++) {
            Asset memory asset = present.assets[i];
            if (asset.token == address(0)) continue; // 跳过ETH

        

            try IERC165(asset.token).supportsInterface(type(IERC721).interfaceId) returns (bool isERC721) {
            if (isERC721) {
                // ERC721 transferFrom 没有返回值
                IERC721(asset.token).transferFrom(address(this), present.sender, asset.amount);
            } else {
                // ERC20 transfer 返回 bool
                require(IERC20(asset.token).transfer(present.sender, asset.amount), "ERC20 transfer failed");
            }
        } catch {
            // 默认按 ERC20 处理
            require(IERC20(asset.token).transfer(present.sender, asset.amount), "ERC20 transfer failed");
        }
    }

        emit TakeBackTest(presentId, msg.sender);
        }
}

