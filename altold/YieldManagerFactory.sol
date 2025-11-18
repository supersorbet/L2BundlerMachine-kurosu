// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {LibClone} from "solady/src/utils/LibClone.sol";

/// @title YieldManagerFactory
/// @notice Factory for deploying user-owned YieldManager clones
/// @dev Uses minimal proxy clones for gas efficiency
/// @author pppcoresrbt
contract YieldManagerFactory is Ownable {
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CUSTOM ERRORS                        */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    error ZeroAddress();
    error DeploymentFailed();
    error AlreadyDeployed();
    error InvalidConfig();

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       CONSTANTS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @dev L2 CrossDomainMessenger (OP address FIX IN FUTURE)
    address private constant L2_MESSENGER = 0x4200000000000000000000000000000000000007;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                       STORAGE                              */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Implementation contract address
    address public implementation;
    /// @notice Protocol addresses (shared across all instances)
    address public tydro;
    address public velodrome;
    address public curve;
    address public relayBridge;
    
    /// @notice Track deployed YieldManagers per user
    mapping(address => address[]) public userYieldManagers;
    /// @notice Track if a contract is deployed by this factory
    mapping(address => bool) public isDeployedByFactory;
    /// @notice Total deployments
    uint256 public totalDeployments;

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                      CONSTRUCTOR                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Deploy factory
    /// @param impl YieldManagerRelay implementation address
    /// @param _tydro Tydro pool address
    /// @param _velo Velodrome router address
    /// @param _curve Curve pool address
    /// @param _relayBridge Relay.link bridge address
    constructor(
        address impl,
        address _tydro,
        address _velo,
        address _curve,
        address _relayBridge
    ) { 
        implementation = impl;
        tydro = _tydro;
        velodrome = _velo;
        curve = _curve;
        relayBridge = _relayBridge;
        
        _initializeOwner(msg.sender);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   DEPLOYMENT FUNCTIONS                     */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Deploy a new YieldManager instance for a user
    /// @param l1Recipient Address to receive bridged funds on L1
    /// @param l1Controller L1 controller address (0 to disable L1 control)
    /// @param salt Salt for CREATE2 deployment
    /// @return yieldManager Address of deployed YieldManager
    function deployYieldManager(
        address l1Recipient,
        address l1Controller,
        bytes32 salt
    ) external returns (address yieldManager) {
        if (l1Recipient == address(0)) revert ZeroAddress();
        bytes memory data = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address,address,address)",
            tydro,
            velodrome,
            curve,
            relayBridge,
            l1Recipient,
            l1Controller,
            L2_MESSENGER,
            msg.sender
        );
        
        yieldManager = LibClone.cloneDeterministic(implementation, salt);
        (bool success, ) = yieldManager.call(data);
        if (!success) revert DeploymentFailed();
        userYieldManagers[msg.sender].push(yieldManager);
        isDeployedByFactory[yieldManager] = true;
        
        unchecked {
            ++totalDeployments;
        }
        
        emit ManagerDeployed(msg.sender, yieldManager, l1Recipient, salt);
    }

    /// @notice Deploy with auto-generated salt (simpler for users)
    /// @param l1Recipient Address to receive bridged funds on L1
    /// @param l1Controller L1 controller address
    /// @return yieldManager Address of deployed YieldManager
    function deployYieldManagerSimple(
        address l1Recipient,
        address l1Controller
    ) external returns (address yieldManager) {
        ///Generate salt from user address & nonce
        bytes32 salt = keccak256(abi.encodePacked(
            msg.sender,
            userYieldManagers[msg.sender].length,
            block.timestamp
        ));
        
        return deployYieldManager(l1Recipient, l1Controller, salt);
    }

    /// @notice Predict the address of a YieldManager deployment
    /// @param salt Salt for CREATE2
    /// @return predicted Predicted address
    function predictYieldManagerAddress(bytes32 salt) 
        external 
        view 
        returns (address predicted) 
    {
        return LibClone.predictDeterministicAddress(implementation, salt, address(this));
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   ADMIN FUNCTIONS                          */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Update implementation contract
    /// @param newImpl New implementation address
    /// @dev Only affects new deployments
    function setImplementation(address newImpl) 
        external 
        onlyOwner 
    {
        if (newImpl == address(0)) revert ZeroAddress();
        address oldImpl = implementation;
        implementation = newImpl;
        
        emit ImplementationUpdated(oldImpl, newImpl);
    }

    /// @notice Update protocol addresses
    /// @param _tydro New Tydro address
    /// @param _velo New Velodrome address
    /// @param _curve New Curve address
    /// @param _relayBridge New Relay bridge address
    function setProtocolConfig(
        address _tydro,
        address _velo,
        address _curve,
        address _relayBridge
    ) external onlyOwner {
        tydro = _tydro;
        velodrome = _velo;
        curve = _curve;
        relayBridge = _relayBridge;
        
        emit ProtocolConfigUpdated(_tydro, _velo, _curve, _relayBridge);
    }

    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                   VIEW FUNCTIONS                           */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    /// @notice Get all YieldManagers deployed by a user
    /// @param user User address
    /// @return Array of YieldManager addresses
    function getUserYieldManagers(address user) 
        external 
        view 
        returns (address[] memory) 
    {
        return userYieldManagers[user];
    }

    /// @notice Get number of YieldManagers deployed by a user
    /// @param user User address
    /// @return count Number of deployments
    function getUserDeploymentCount(address user) 
        external 
        view 
        returns (uint256 count) 
    {
        return userYieldManagers[user].length;
    }

    /// @notice Check if factory is properly configured
    /// @return configured True if all addresses are set
    function isConfigured() external view returns (bool configured) {
        return implementation != address(0)
            && tydro != address(0)
            && velodrome != address(0)
            && curve != address(0)
            && relayBridge != address(0);
    }
    
    /*´:°•.°+.*•´.*:˚.°*.˚•´.°:°•.°•.*•´.*:˚.°*.˚•´.°:°•.°+.*•´.*:*/
    /*                          EVENTS                            */
    /*.•°:°.´+˚.*°.˚:*.´•*.+°.•°:´*.´•*.•°.•°:°.´:•˚°.*°.˚:*.´+°.•*/

    event ManagerDeployed(
        address indexed owner,
        address indexed yieldManager,
        address indexed l1Recipient,
        bytes32 salt
    );
    event ImplementationUpdated(address indexed oldImpl, address indexed newImpl);
    event ProtocolConfigUpdated(
        address tydro,
        address velo,
        address curve,
        address relayBridge
    );
}
