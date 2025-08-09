# 🎁 Present NFT Project

一个基于以太坊的数字礼物 NFT 系统，让你可以将礼物包装成 NFT 并送给别人拆开。
我送礼物就会生成一个nft证明我确实送出去礼物，我拆开礼物就生成一个nft证明我拆开礼物.

## 🌟 项目亮点

- 🎁 **包装礼物**：将任何数字资产包装成神秘的礼物 NFT
- 🎉 **拆开惊喜**：收礼人可以拆开礼物查看里面的内容  
- 🎨 **动态艺术**：自动生成的 SVG 艺术，包装前后样式不同
- 🔒 **安全可靠**：基于 OpenZeppelin 标准合约

## 📖 Overview

This project implements a digital present system where users can:
- Wrap presents as NFTs with hidden content
- Unwrap presents to reveal the contents
- Take back unopened presents
- Generate dynamic SVG-based NFT artwork

## 🏗️ Architecture

- **WrappedPresentNFT**: NFTs representing unopened presents
- **UnwrappedPresentNFT**: NFTs representing opened presents  
- **PresentManager**: Main contract handling wrapping/unwrapping logic

## 🚀 Quick Start

### Prerequisites
- [Foundry](https://getfoundry.sh/) installed
- Git installed

### Installation

```bash
# Clone the repository
git clone <your-repo-url>
cd present-nft-project

# Install dependencies
forge install

# Build the project
forge build
```

### Testing

```bash
# Run all tests
forge test

# Run tests with verbose output
forge test -vv

# Run specific test file
forge test --match-path test/WrappedPresentNFT.t.sol

# Check test coverage
forge coverage
```

### Deployment

```bash
# Deploy to local network (Anvil)
forge script script/Deploy.s.sol --fork-url http://localhost:8545 --broadcast

# Deploy to testnet
forge script script/Deploy.s.sol --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY --broadcast
```

## 📋 Contract Addresses

### Mainnet
- Coming soon...

### Sepolia Testnet
- WrappedPresentNFT: `0x...`
- UnwrappedPresentNFT: `0x...`
- PresentManager: `0x...`

## 🔧 Configuration

Copy `.env.example` to `.env` and fill in your values:

```bash
cp .env.example .env
```

## 📚 Documentation

### Main Functions

#### WrappedPresentNFT
- `mint()` - Create a new wrapped present NFT
- `getUserNFTs()` - Get all NFTs owned by user
- `getPresentInfo()` - Get present metadata

#### UnwrappedPresentNFT  
- `mint()` - Create unwrapped present NFT
- `getUnwrappedInfo()` - Get unwrapped present details

### Events
- `PresentWrapped(address indexed sender, address indexed recipient, uint256 tokenId)`
- `PresentUnwrapped(address indexed opener, uint256 tokenId)`

## 🧪 Testing

Our test suite includes:
- Unit tests for all contract functions
- Integration tests for cross-contract interactions
- Fuzz testing for edge cases
- Gas optimization tests

Test coverage: **95%+**

## 🔐 Security

⚠️ **Warning**: This contract is for educational purposes and has not been audited. The developer acknowledges potential security risks.

For production use, consider:
- Professional security audit
- Multi-sig implementation
- Access control improvements
- Rate limiting

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- OpenZeppelin for secure contract templates
- Foundry team for the excellent development framework
- The Ethereum community for continuous innovation

## 📞 Contact

- Developer: [Your Name]
- Email: your.email@example.com
- Twitter: [@yourhandle]

---

**Built with ❤️ using Foundry**