// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0; 

import "@openzeppelin/contracts/utils/Strings.sol";

import "../matic/IChildToken.sol";
import "../matic/common/AccessControlMixin.sol";
import "../matic/common/ContextMixin.sol";
import "../matic/common/NativeMetaTransaction.sol";

import './ERC1155.sol';
import './ERC1155Metadata.sol';
import './ERC1155MintBurn.sol';

 
contract OwnableDelegateProxy { }

contract ProxyRegistry {
  mapping(address => OwnableDelegateProxy) public proxies;
}

/**
 * @title ERC1155Tradable
 * Supports ChildMintable functions for Matic
 * ERC1155Tradable - ERC1155 contract that whitelists an operator address, has create and mint functionality, and supports useful standards from OpenZeppelin,
  like name(), symbol(), and totalSupply()
 */
contract ERC1155Tradable is 
  IChildToken, 
  NativeMetaTransaction, 
  ContextMixin, 
  AccessControlMixin, 
  ERC1155, 
  ERC1155MintBurn, 
  ERC1155Metadata 
{

  using Strings for uint256;

  address proxyRegistryAddress;
  uint256 private _currentTokenID;
  mapping (uint256 => uint256) public tokenSupply;

  // Contract name
  string public name;
  // Contract symbol
  string public symbol;

  bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");

  /**
   * @dev Require_msgSender() to own more than 0 of the token id
   */
  modifier ownersOnly(uint256 _id) {
    require(balances[msg.sender][_id] > 0, "ERC1155Tradable#ownersOnly: ONLY_OWNERS_ALLOWED");
    _;
  }

  constructor(
    string memory _name,
    string memory _symbol,
    string memory _metadataURI,
    address _childChainManager, //for matic
    address _proxyRegistryAddress //for opensea
  ) {
    name = _name;
    symbol = _symbol;
    proxyRegistryAddress = _proxyRegistryAddress;
    _setupContractId("ChildMintableERC1155");
    _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    _setupRole(DEPOSITOR_ROLE, _childChainManager);
    _setBaseMetadataURI(_metadataURI);
    _initializeEIP712(_metadataURI);
  }

  function uri(
    uint256 _id
  ) public view override returns (string memory) {
    require(_currentTokenID >= _id, "Token id has not been yet created");
    return bytes(baseMetadataURI).length > 0 ? string(abi.encodePacked(baseMetadataURI, _id.toString())) : "";
  }

  /**
    * @dev Returns the total quantity for a token ID
    * @param _id uint256 ID of the token to query
    * @return amount of token in existence
    */
  function totalSupply(
    uint256 _id
  ) public view returns (uint256) {
    return tokenSupply[_id];
  }

  /**
   * @dev Will update the base URL of token's URI
   * @param _newBaseMetadataURI New base URL of token's URI
   */
  function setBaseMetadataURI(
    string memory _newBaseMetadataURI
  ) public only(DEFAULT_ADMIN_ROLE) {
    _setBaseMetadataURI(_newBaseMetadataURI);
  }

  /**
    * @dev Creates a new token type and assigns _initialSupply to an address
    * NOTE: remove onlyOwner if you want third parties to create new tokens on your contract (which may change your IDs)
    * @param _initialOwner address of the first owner of the token
    * @param _initialSupply amount to supply the first owner
    * @return The newly created token ID
    */
  function create(
    address _initialOwner,
    uint256 _initialSupply
  ) external only(DEFAULT_ADMIN_ROLE) returns (uint256)  {

    uint256 _id = getNextTokenID(); 
    _incrementTokenTypeId();

    _mint(_initialOwner, _id, _initialSupply, "");
    tokenSupply[_id] = _initialSupply;
    return _id;
  }

  /**
    * @dev Mints some amount of tokens to an address
    * @param _to          Address of the future owner of the token
    * @param _id          Token ID to mint
    * @param _quantity    Amount of tokens to mint
    */
  function mint(
    address _to,
    uint256 _id,
    uint256 _quantity
  ) public only(DEFAULT_ADMIN_ROLE) {
    _mint(_to, _id, _quantity, "");
    tokenSupply[_id] += _quantity;
  }

  /**
    * @dev Mint tokens for each id in _ids
    * @param _to          The address to mint tokens to
    * @param _ids         Array of ids to mint
    * @param amounts      Array of amounts of tokens to mint per id
    */
  function batchMint(
    address _to,
    uint256[] memory _ids,
    uint256[] memory amounts
  ) public only(DEFAULT_ADMIN_ROLE) {
    for (uint256 i = 0; i < _ids.length; i++) {
      uint256 _id = _ids[i];
      uint256 quantity = amounts[i];
      tokenSupply[_id] += quantity;
    }
    _batchMint(_to, _ids, amounts, "");
  }

  /**
   * Override isApprovedForAll to whitelist user's OpenSea proxy accounts to enable gas-free listings.
   */
  function isApprovedForAll(
    address _owner,
    address _operator
  ) public override(ERC1155) view returns (bool isOperator) {
    // Whitelist OpenSea proxy contract for easy trading.
    ProxyRegistry proxyRegistry = ProxyRegistry(proxyRegistryAddress);
    if (address(proxyRegistry.proxies(_owner)) == _operator) {
      return true;
    }

    return ERC1155.isApprovedForAll(_owner, _operator);
  }

  /**
    * @dev calculates the next token ID based on value of _currentTokenID
    * @return uint256 for the next token ID
    */
  function getNextTokenID() public view returns (uint256) {
    return _currentTokenID + 1;
  }

  /**
    * @dev increments the value of _currentTokenID
    */
  function _incrementTokenTypeId() private  {
    _currentTokenID++;
  }

    /***********************************|
    |          Matic Functions          |
    |___________________________________*

    /**
     * @notice called when tokens are deposited on root chain
     * @dev Should be callable only by ChildChainManager
     * Should handle deposit by minting the required tokens for user
     * Make sure minting is done only by this function
     * @param user user address for whom deposit is being done
     * @param depositData abi encoded ids array and amounts array
     */
    function deposit(address user, bytes calldata depositData) external override only(DEPOSITOR_ROLE) {
      (
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
      ) = abi.decode(depositData, (uint256[], uint256[], bytes));

      require(
        user != address(0),
        "ChildMintableERC1155: INVALID_DEPOSIT_USER"
      );

      _batchMint(user, ids, amounts, data);
    }

    // This is to support Native meta transactions
    // never use msg.sender directly, use _msgSender() instead
    function _msgSender() internal override view returns (address sender) {
        return ContextMixin.msgSender();
    }

    /**
     * @notice called when user wants to withdraw single token back to root chain
     * @dev Should burn user's tokens. This transaction will be verified when exiting on root chain
     * @param id id to withdraw
     * @param amount amount to withdraw
     */
    function withdrawSingle(uint256 id, uint256 amount) external {
        _burn(_msgSender(), id, amount);
    }

    /**
     * @notice called when user wants to batch withdraw tokens back to root chain
     * @dev Should burn user's tokens. This transaction will be verified when exiting on root chain
     * @param ids ids to withdraw
     * @param amounts amounts to withdraw
     */
    function withdrawBatch(uint256[] calldata ids, uint256[] calldata amounts) external {
        _batchBurn(_msgSender(), ids, amounts);
    }

    /**
     * @notice See definition of `_mint` in ERC1155 contract
     * @dev This implementation only allows admins to mint tokens
     * but can be changed as per requirement
     */
    function mint(
        address account,
        uint256 id,
        uint256 amount,
        bytes calldata data
    ) external only(DEFAULT_ADMIN_ROLE) {
        _mint(account, id, amount, data);
    }

    /**
     * @notice See definition of `_mintBatch` in ERC1155 contract
     * @dev This implementation only allows admins to mint tokens
     * but can be changed as per requirement
     */
    function mintBatch(
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external only(DEFAULT_ADMIN_ROLE) {
        _batchMint(to, ids, amounts, data);
    }


  /***********************************|
  |          ERC165 Functions         |
  |__________________________________*/

  /**
   * @notice Query if a contract implements an interface
   * @param _interfaceID  The interface identifier, as specified in ERC-165
   * @return `true` if the contract implements `_interfaceID` and
   */
  function supportsInterface(bytes4 _interfaceID) public override(ERC1155, ERC1155Metadata, AccessControl) virtual view returns (bool) {
    if (_interfaceID == type(IERC1155).interfaceId) {
      return true;
    }
    return super.supportsInterface(_interfaceID);
  }
  
}