// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {OfferForwarderTest} from "@mgv-strats/test/strategies/unit/OfferForwarder.t.sol";
import {SimpleAaveLogic} from "@mgv-strats/src/strategies/routing_logic/SimpleAaveLogic.sol";
import {IPoolAddressesProvider} from "@mgv-strats/src/strategies/vendor/aave/v3/IPoolAddressesProvider.sol";
import {IPool} from "@mgv-strats/src/strategies/vendor/aave/v3/IPool.sol";
import {TransferLib} from "@mgv/lib/TransferLib.sol";
import {AbstractRouter, RL} from "@mgv-strats/src/strategies/routers/abstract/AbstractRouter.sol";
import {MgvLib, IERC20, OLKey, Offer, OfferDetail} from "@mgv/src/core/MgvLib.sol";
import {PinnedPolygonFork} from "@mgv/test/lib/forks/Polygon.sol";

abstract contract BaseSimpleAaveLogic_Test is OfferForwarderTest {
  IPool public aave;
  SimpleAaveLogic public aaveLogic;

  function overlying(IERC20 asset) public view returns (IERC20 aToken) {
    aToken = IERC20(aave.getReserveData(address(asset)).aTokenAddress);
  }

  function _approveLender(IERC20 token, uint amount) internal {
    TransferLib.approveToken(token, address(aave), amount);
  }

  function dealAToken(IERC20 token, uint amount, address to) internal {
    deal($(token), $(this), amount);
    _approveLender(token, amount);
    aave.supply(address(token), amount, to, 0);
  }

  function setupMakerContract() internal virtual override {
    aave = IPool(IPoolAddressesProvider(fork.get("AaveAddressProvider")).getPool());
    super.setupMakerContract();
    aaveLogic = new SimpleAaveLogic(fork.get("AaveAddressProvider"), 2);
  }

  function setUp() public virtual override {
    fork = new PinnedPolygonFork(39880000);
    super.setUp();
  }
}

contract FullAaveLogic_Test is BaseSimpleAaveLogic_Test {
  function fundStrat() internal virtual override {
    dealAToken(weth, 1 ether, owner);
    dealAToken(usdc, cash(usdc, 2000), owner);
    IERC20 aWeth = overlying(weth);
    IERC20 aUsdc = overlying(usdc);
    vm.startPrank(owner);
    aWeth.approve(address(ownerProxy), type(uint).max);
    aUsdc.approve(address(ownerProxy), type(uint).max);
    vm.stopPrank();
  }

  function chooseLogic(uint offerId) internal virtual override {
    setRouterLogic(offerId, aaveLogic, aaveLogic);
  }
}
