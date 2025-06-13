// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { Script } from "forge-std/Script.sol";

abstract contract DeployScript is Script {
    using Strings for uint256;

    uint256 public chainID;
    uint256 public deployerKey;
    address public deployerAddress;

    // cache for implementation addresses read from deploys txt files
    mapping(bytes32 => address) internal _cachedImpl;

    function setUp() public virtual {
        chainID = vm.envUint("CHAIN_ID");
        deployerKey = vm.envUint("PRIVATE_KEY");
        deployerAddress = vm.addr(deployerKey);
    }

    function run() public virtual {
        vm.startBroadcast(deployerAddress);

        deploy();

        vm.stopBroadcast();

        writeDeploymentDetailsToFile();
    }

    function deploy() internal virtual;

    function writeDeploymentDetailsToFile() internal virtual {
        string memory filePath = string(
            abi.encodePacked("deploys/", getContractName(), ".", chainID.toString(), ".txt")
        );
        vm.writeFile(filePath, "");
        writeAdditionalDeploymentDetails(filePath);
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal virtual;

    function getContractName() internal virtual returns (string memory);

    function addressToString(address _addr) internal pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint256 i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint256(uint160(_addr)) / (2 ** (8 * (19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2 * i] = char(hi);
            s[2 * i + 1] = char(lo);
        }
        return string(abi.encodePacked("0x", string(s)));
    }

    function char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }

    /// @dev Read implementation address from deploys/<label>.<chainID>.txt file where first 0x... address is parsed.
    function _loadImplementation(string memory label) internal returns (address impl) {
        bytes32 key = keccak256(abi.encodePacked(label));
        impl = _cachedImpl[key];
        if (impl == address(0)) {
            string memory filePath = string(
                abi.encodePacked("deploys/", label, ".", Strings.toString(chainID), ".txt")
            );
            string memory fileData = vm.readFile(filePath);
            bytes memory b = bytes(fileData);
            uint256 start;
            for (uint256 i = 0; i + 1 < b.length; i++) {
                if (b[i] == "0" && b[i + 1] == "x") {
                    start = i;
                    break;
                }
            }
            bytes memory addrBytes = new bytes(42);
            for (uint256 j = 0; j < 42 && start + j < b.length; j++) {
                addrBytes[j] = b[start + j];
            }
            impl = vm.parseAddress(string(addrBytes));
            _cachedImpl[key] = impl;
        }
    }
}
