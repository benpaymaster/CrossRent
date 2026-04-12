// SPDX-License-Identifier: MIT
pragma solidity ^0.8.34;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";

contract RentYieldHook is BaseHook {
    
    struct RentPosition {
        uint256 principal;
        uint256 startTime;
        address beneficiary; // Tenant or Landlord
    }

    // Mapping: PoolId => userAddress => Position
    mapping(address => RentPosition) public rentPositions;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: true, 
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: true, // Need this to settle the final yield
            beforeSwap: false,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override returns (bytes4) {
        // Extract the beneficiary from hookData (passed from your Escrow contract)
        address beneficiary = abi.decode(hookData, (address));

        // Logic: Record the entry point for yield calculation
        // params.liquidity is the amount of 'capital' now earning fees
        rentPositions[beneficiary] = RentPosition({
            principal: uint256(params.liquidity),
            startTime: block.timestamp,
            beneficiary: beneficiary
        });

        return BaseHook.afterAddLiquidity.selector;
    }

    // NEW: Calculate the accrued yield based on a 5.5% Target APY for the MVP
    function getAccruedYield(address user) public view returns (uint256) {
        RentPosition storage pos = rentPositions[user];
        if (pos.startTime == 0) return 0;

        uint256 duration = block.timestamp - pos.startTime;
        // Simple linear yield for MVP: (Principal * APY * duration) / (1 year)
        // APY = 550 (5.5%)
        return (pos.principal * 550 * duration) / (365 days * 10000);
    }
}