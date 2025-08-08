// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title MockPresentNFT
 * @dev 用于测试的简单ERC721代币实现
 */
contract MockPresentNFT {
    string public name;
    string public symbol;
    
    // 代币ID到所有者的映射
    mapping(uint256 => address) private _owners;
    // 所有者到代币数量的映射
    mapping(address => uint256) private _balances;
    // 代币ID到授权地址的映射
    mapping(uint256 => address) private _tokenApprovals;
    // 所有者到操作员授权的映射
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    // 代币ID到礼物ID的映射
    mapping(uint256 => bytes32) private _presentIds;
    // 礼物ID到代币ID的映射
    mapping(bytes32 => uint256) private _tokenIds;
    
    // 当前代币ID
    uint256 private _currentTokenId;
    // Present合约地址
    address private _presentContract;
    
    // 事件
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
    
    constructor(string memory _name, string memory _symbol) {
        name = _name;
        symbol = _symbol;
        _currentTokenId = 1;
    }
    
    // 设置Present合约地址
    function setPresentContract(address presentContract) external {
        require(_presentContract == address(0), "Present contract already set");
        _presentContract = presentContract;
    }
    
    // 查询所有者
    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721: owner query for nonexistent token");
        return owner;
    }
    
    // 查询余额
    function balanceOf(address owner) public view returns (uint256) {
        require(owner != address(0), "ERC721: balance query for the zero address");
        return _balances[owner];
    }
    
    // 查询代币对应的礼物ID
    function presentIdOf(uint256 tokenId) public view returns (bytes32) {
        require(_exists(tokenId), "ERC721: query for nonexistent token");
        return _presentIds[tokenId];
    }
    
    // 查询礼物ID对应的代币ID
    function tokenIdOf(bytes32 presentId) public view returns (uint256) {
        uint256 tokenId = _tokenIds[presentId];
        require(tokenId != 0, "ERC721: query for nonexistent present");
        return tokenId;
    }
    
    // 铸造代币
    function mint(address to, bytes32 presentId) public returns (uint256) {
        // 仅Present合约或当前无限制时可调用
        require(
            _presentContract == address(0) || msg.sender == _presentContract, 
            "Only present contract can mint"
        );
        
        uint256 tokenId = _currentTokenId;
        _mint(to, tokenId);
        _presentIds[tokenId] = presentId;
        _tokenIds[presentId] = tokenId;
        
        _currentTokenId++;
        return tokenId;
    }
    
    // 内部铸造函数
    function _mint(address to, uint256 tokenId) internal {
        require(to != address(0), "ERC721: mint to the zero address");
        require(!_exists(tokenId), "ERC721: token already minted");
        
        _balances[to] += 1;
        _owners[tokenId] = to;
        
        emit Transfer(address(0), to, tokenId);
    }
    
    // 检查代币是否存在
    function _exists(uint256 tokenId) internal view returns (bool) {
        return _owners[tokenId] != address(0);
    }
} 