pragma solidity >=0.4.21 <0.6.0;

import "../../node_modules/openzeppelin-solidity/contracts/ownership/Ownable.sol";
import "../../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract Exchange is Ownable {
    using SafeMath for uint256;
    string constant public VERSION = "1.0.0-alpha";

    struct swapWrapper {
        uint256 _tokenAmount;
        address _owner;
    }

    struct Indexer {
        mapping(uint256 => swapWrapper) _swapWrappers;

        uint256 _indexerPos;
        uint256 _indexerLength;

        uint256 _higherPrice;
        uint256 _lowerPrice;
    }

    struct tokenWrapper {
        // General information about the token
        address _contractAddress;
        string _symbolName;

        /* We need two seperate indexes for 2 purposes: 
         *
         */
        
        mapping (uint256 => Indexer) _buyIndex;
        uint256 _currentBuyPrice;
        uint256 _lowestBuyPrice;
        uint256 _totalBuyAmount;

        mapping (uint256 => Indexer) _sellIndex;
        uint256 _currentSellPrice;
        uint256 _lowestSellPrice;
        uint256 _totalSellAmount;

    }

    mapping (uint16 => tokenWrapper) _tokens;
    uint16 _tokenSymbolIndex;

    mapping (address => uint256) _ETHBalance;
    mapping (address => mapping (uint16 => uint256)) _tokenBalance;

    // Withdrawal and Deposit ETH
    function depositETH() public payable {
        _ETHBalance[msg.sender] = _ETHBalance[msg.sender].add(msg.value);
    }

    function withdrawETH(uint256 amountInWei) public {
        require(_ETHBalance[msg.sender] >= amountInWei);
        _ETHBalance[msg.sender] = _ETHBalance[msg.sender].sub(amountInWei);
        msg.sender.transfer(amountInWei);
    }

    function getETHBalance() public view returns (uint256) {
        return _ETHBalance[msg.sender];
    }

}
