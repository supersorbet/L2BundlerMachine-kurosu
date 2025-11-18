// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IYieldStrategy} from "../interfaces/IYieldStrategy.sol";
import {IVotingEscrow, IVeloGauge} from "../interfaces/IVelodrome.sol";
import {SafeTransferLib} from "solady/src/utils/SafeTransferLib.sol";

/// @title VelodromeVELOStakingStrategy
/// @notice Strategy for staking VELO tokens in VotingEscrow (veVELO) for governance and rewards
/// @dev Strategy ID: 3
/// @dev auxData format: abi.encode(unlockTime) where unlockTime is uint256 (timestamp)
contract VelodromeVELOStakingStrategy is IYieldStrategy {
    using SafeTransferLib for address;
    
    address public immutable VOTING_ESCROW;
    address public immutable VELO_TOKEN;
    
    mapping(address => uint256) public veNFTIds;
    
    error DepositFailed();
    error WithdrawFailed();
    error InvalidUnlockTime();
    error NoPosition();
    
    constructor(address _votingEscrow, address _veloToken) {
        VOTING_ESCROW = _votingEscrow;
        VELO_TOKEN = _veloToken;
    }
    
    function strategyId() external pure returns (uint8) {
        return 3;
    }
    
    function deposit(address token, uint256 amount, bytes calldata auxData) external returns (uint256 shares) {
        if (token != VELO_TOKEN) revert DepositFailed();
        
        uint256 unlockTime = abi.decode(auxData, (uint256));
        if (unlockTime <= block.timestamp) revert InvalidUnlockTime();
        if (unlockTime > block.timestamp + 4 * 365 days) revert InvalidUnlockTime();
        
        SafeTransferLib.safeTransferFrom(VELO_TOKEN, msg.sender, address(this), amount);
        SafeTransferLib.safeApprove(VELO_TOKEN, VOTING_ESCROW, amount);
        
        uint256 tokenId = veNFTIds[msg.sender];
        if (tokenId == 0) {
            tokenId = IVotingEscrow(VOTING_ESCROW).createLock(amount, unlockTime);
            veNFTIds[msg.sender] = tokenId;
        } else {
            IVotingEscrow(VOTING_ESCROW).increaseAmount(tokenId, amount);
            IVotingEscrow(VOTING_ESCROW).increaseUnlockTime(tokenId, unlockTime);
        }
        
        return IVotingEscrow(VOTING_ESCROW).balanceOfNFT(tokenId);
    }
    
    function withdraw(address token, uint256 shares, bytes calldata auxData) external returns (uint256 amount) {
        if (token != VELO_TOKEN) revert WithdrawFailed();
        
        uint256 tokenId = veNFTIds[msg.sender];
        if (tokenId == 0) revert NoPosition();
        
        (int128 lockedAmount, uint256 unlockTime) = IVotingEscrow(VOTING_ESCROW).locked(tokenId);
        if (block.timestamp < unlockTime) revert WithdrawFailed();
        
        IVotingEscrow(VOTING_ESCROW).withdraw(tokenId);
        uint256 withdrawn = uint256(uint128(lockedAmount));
        
        SafeTransferLib.safeTransfer(VELO_TOKEN, msg.sender, withdrawn);
        
        veNFTIds[msg.sender] = 0;
        
        return withdrawn;
    }
    
    function harvest(address token, bytes calldata auxData) external returns (uint256 harvested) {
        return 0;
    }
    
    function getAPY(address token, bytes calldata auxData) external view returns (uint256 apyBps) {
        return 500;
    }
    
    function getPrincipal(address token) external view returns (uint256) {
        uint256 tokenId = veNFTIds[msg.sender];
        if (tokenId == 0) return 0;
        return IVotingEscrow(VOTING_ESCROW).balanceOfNFT(tokenId);
    }
    
    function getBalance(address token, bytes calldata auxData) external view returns (uint256 balance) {
        if (token != VELO_TOKEN) return 0;
        uint256 tokenId = veNFTIds[msg.sender];
        if (tokenId == 0) return 0;
        return IVotingEscrow(VOTING_ESCROW).balanceOfNFT(tokenId);
    }
    
    function getAvailableYield(address token, bytes calldata auxData) external view returns (uint256 yield) {
        return 0; // veVELO doesn't have claimable yield
    }
    
    function supportsToken(address token, bytes calldata auxData) external view returns (bool supported) {
        return token == VELO_TOKEN;
    }
    
    function strategyName() external pure returns (string memory) {
        return "Velodrome VELO Staking";
    }
}
