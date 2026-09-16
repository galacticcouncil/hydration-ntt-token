// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
// console2, not console: forge-std 1.7.6's console.sol encodes uint logs as
// "log(string,uint)", which no cheatcode handler matches, so they silently vanish.
import {console2 as console} from "forge-std/console2.sol";
import {PeerTokenHydration} from "../src/PeerTokenHydration.sol";

/// @dev Minimal view surface of the NTT manager, used only to sanity-check the
/// address before handing it mint rights.
interface INttManagerLike {
    function token() external view returns (address);
    function getMode() external view returns (uint8);
    function tokenDecimals() external view returns (uint8);
}

/// @notice Step 1 — deploy the HDX peer token with the deployer as interim minter.
///
/// Required env:
///   PRIVATE_KEY   deployer key (uint256, 0x-prefixed hex is fine)
///   TOKEN_OWNER   owner address — use a multisig, this key controls setMinter forever
/// Optional env:
///   TOKEN_NAME    default "Hydration"
///   TOKEN_SYMBOL  default "HDX"
///   TOKEN_MINTER  default = deployer, handed to the NttManager later via SetMinterHydration
contract DeployPeerHydration is Script {
    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        string memory name = vm.envOr("TOKEN_NAME", string("Hydration"));
        string memory symbol = vm.envOr("TOKEN_SYMBOL", string("HDX"));
        address owner = vm.envAddress("TOKEN_OWNER");
        address minter = vm.envOr("TOKEN_MINTER", deployer);

        require(owner != address(0), "TOKEN_OWNER must not be zero");
        require(minter != address(0), "TOKEN_MINTER must not be zero");

        console.log("chain id     ", block.chainid);
        console.log("deployer     ", deployer);
        console.log("owner        ", owner);
        console.log("interim minter", minter);

        if (owner.code.length == 0) {
            console.log("");
            console.log("WARNING: TOKEN_OWNER is an EOA, not a contract.");
            console.log("It can repoint the minter and mint without limit, forever.");
            console.log("Use a multisig for mainnet.");
        }

        vm.startBroadcast(pk);
        PeerTokenHydration token = new PeerTokenHydration(name, symbol, minter, owner);
        vm.stopBroadcast();

        // fail loudly here rather than after the manager is wired up
        require(token.decimals() == 12, "decimals != 12");
        require(token.owner() == owner, "owner mismatch");
        require(token.minter() == minter, "minter mismatch");
        require(token.totalSupply() == 0, "unexpected initial supply");

        console.log("");
        console.log("PeerTokenHydration deployed:", address(token));
        console.log("decimals    ", token.decimals());
        console.log("");
        console.log("Next: deploy the NttManager, then run SetMinterHydration.");
    }
}

/// @notice Step 2 — hand mint rights to the NttManager once `ntt add-chain` has deployed it.
///
/// Must be broadcast by TOKEN_OWNER (setMinter is onlyOwner). If the owner is a
/// multisig, use this script's checks to validate, then submit the call there
/// instead of broadcasting.
///
/// Required env:
///   PRIVATE_KEY    owner key
///   TOKEN_ADDRESS  the deployed PeerTokenHydration
///   NTT_MANAGER    the NttManager proxy on this chain
contract SetMinterHydration is Script {
    function run() public {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address caller = vm.addr(pk);
        address tokenAddr = vm.envAddress("TOKEN_ADDRESS");
        address manager = vm.envAddress("NTT_MANAGER");

        PeerTokenHydration token = PeerTokenHydration(tokenAddr);

        require(token.owner() == caller, "caller is not the token owner");
        require(manager.code.length > 0, "NTT_MANAGER has no code");

        // Guard against pointing the minter at the wrong address. The manager must
        // reference this exact token, be in burning mode, and agree on decimals.
        try INttManagerLike(manager).token() returns (address managed) {
            require(managed == tokenAddr, "manager.token() != TOKEN_ADDRESS");
        } catch {
            revert("NTT_MANAGER does not expose token() - wrong address?");
        }

        require(INttManagerLike(manager).getMode() == 1, "manager is not in burning mode");
        require(INttManagerLike(manager).tokenDecimals() == 12, "manager tokenDecimals != 12");

        console.log("token       ", tokenAddr);
        console.log("old minter  ", token.minter());
        console.log("new minter  ", manager);

        vm.startBroadcast(pk);
        token.setMinter(manager);
        vm.stopBroadcast();

        require(token.minter() == manager, "setMinter did not take effect");
        console.log("minter is now the NttManager");
    }
}
