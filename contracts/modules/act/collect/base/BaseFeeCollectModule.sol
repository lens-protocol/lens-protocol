// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import {Errors} from 'contracts/modules/constants/Errors.sol';
import {FeeModuleBase} from 'contracts/modules/FeeModuleBase.sol';
import {ICollectModule} from 'contracts/modules/interfaces/ICollectModule.sol';
import {ActionRestricted} from 'contracts/modules/ActionRestricted.sol';

import {ModuleTypes} from 'contracts/modules/libraries/constants/ModuleTypes.sol';

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC721} from '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import {SafeERC20} from '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {FollowValidationLib} from 'contracts/modules/libraries/FollowValidationLib.sol';

import {BaseFeeCollectModuleInitData, BaseProfilePublicationData, IBaseFeeCollectModule} from 'contracts/modules/interfaces/IBaseFeeCollectModule.sol';

/**
 * @title BaseFeeCollectModule
 * @author Lens Protocol
 *
 * @notice This is base Lens CollectModule implementation, allowing customization of time to collect, number of collects
 * and Followers-only restriction. Charges a fee for collect and distributing it among Receiver/Referrals/Treasury.
 * @dev Here we use "Base" terminology to anything that represents this base functionality (base structs,
 * base functions, base storage). Other collect modules can be built on top of the "Base" by inheriting from this
 * contract and overriding functions.
 * This contract is marked "abstract" as it requires you to implement initializePublicationCollectModule and
 * getPublicationData functions when you inherit from it. See SimpleFeeCollectModule as an example implementation.
 */
abstract contract BaseFeeCollectModule is FeeModuleBase, ActionRestricted, IBaseFeeCollectModule {
    using SafeERC20 for IERC20;

    address immutable HUB;

    mapping(uint256 => mapping(uint256 => BaseProfilePublicationData)) internal _dataByPublicationByProfile;

    constructor(
        address hub,
        address actionModule,
        address moduleRegistry
    ) ActionRestricted(actionModule) FeeModuleBase(hub, moduleRegistry) {
        HUB = hub;
    }

    function supportsInterface(bytes4 interfaceID) public pure virtual returns (bool) {
        return interfaceID == type(ICollectModule).interfaceId;
    }

    /**
     * @inheritdoc ICollectModule
     * @notice Processes a collect by:
     *  1. Validating that collect action meets all needed criteria
     *  2. Processing the collect action either with or without referral
     *
     * @param processCollectParams Collect action parameters (see ModuleTypes.ProcessCollectParams struct)
     */
    function processCollect(
        ModuleTypes.ProcessCollectParams calldata processCollectParams
    ) external virtual onlyActionModule returns (bytes memory) {
        _validateAndStoreCollect(processCollectParams);

        if (processCollectParams.referrerProfileIds.length == 0) {
            _processCollect(processCollectParams);
        } else {
            _processCollectWithReferral(processCollectParams);
        }
        return '';
    }

    /// @inheritdoc IBaseFeeCollectModule
    function getBasePublicationData(
        uint256 profileId,
        uint256 pubId
    ) public view virtual returns (BaseProfilePublicationData memory) {
        return _dataByPublicationByProfile[profileId][pubId];
    }

    /// @inheritdoc IBaseFeeCollectModule
    function calculateFee(
        ModuleTypes.ProcessCollectParams calldata processCollectParams
    ) public view virtual returns (uint160) {
        return
            _dataByPublicationByProfile[processCollectParams.publicationCollectedProfileId][
                processCollectParams.publicationCollectedId
            ].amount;
    }

    /**
     * @dev Validates the Base parameters like:
     * 1) Is the currency whitelisted
     * 2) Is the referralFee in valid range
     * 3) Is the end of collects timestamp in valid range
     *
     * This should be called during initializePublicationCollectModule()
     *
     * @param baseInitData Module initialization data (see BaseFeeCollectModuleInitData struct)
     */
    function _validateBaseInitData(BaseFeeCollectModuleInitData memory baseInitData) internal virtual {
        if (
            (baseInitData.amount == 0 && baseInitData.currency != address(0)) ||
            (baseInitData.amount != 0 && baseInitData.currency == address(0)) ||
            baseInitData.referralFee > BPS_MAX ||
            (baseInitData.endTimestamp != 0 && baseInitData.endTimestamp < block.timestamp)
        ) {
            revert Errors.InitParamsInvalid();
        }
        _verifyErc20Currency(baseInitData.currency);
    }

    /**
     * @dev Stores the initial module parameters
     *
     * This should be called during initializePublicationCollectModule()
     *
     * @param profileId The token ID of the profile publishing the publication.
     * @param pubId The publication ID.
     * @param baseInitData Module initialization data (see BaseFeeCollectModuleInitData struct)
     */
    function _storeBasePublicationCollectParameters(
        uint256 profileId,
        uint256 pubId,
        BaseFeeCollectModuleInitData memory baseInitData
    ) internal virtual {
        _dataByPublicationByProfile[profileId][pubId].amount = baseInitData.amount;
        _dataByPublicationByProfile[profileId][pubId].collectLimit = baseInitData.collectLimit;
        _dataByPublicationByProfile[profileId][pubId].currency = baseInitData.currency;
        _dataByPublicationByProfile[profileId][pubId].recipient = baseInitData.recipient;
        _dataByPublicationByProfile[profileId][pubId].referralFee = baseInitData.referralFee;
        _dataByPublicationByProfile[profileId][pubId].followerOnly = baseInitData.followerOnly;
        _dataByPublicationByProfile[profileId][pubId].endTimestamp = baseInitData.endTimestamp;
    }

    /**
     * @dev Validates the collect action by checking that:
     * 1) the collector is a follower (if enabled)
     * 2) the number of collects after the action doesn't surpass the collect limit (if enabled)
     * 3) the current block timestamp doesn't surpass the end timestamp (if enabled)
     *
     * This should be called during processCollect()
     */
    function _validateAndStoreCollect(ModuleTypes.ProcessCollectParams calldata processCollectParams) internal virtual {
        uint96 collectsAfter = ++_dataByPublicationByProfile[processCollectParams.publicationCollectedProfileId][
            processCollectParams.publicationCollectedId
        ].currentCollects;

        if (
            _dataByPublicationByProfile[processCollectParams.publicationCollectedProfileId][
                processCollectParams.publicationCollectedId
            ].followerOnly
        ) {
            FollowValidationLib.validateIsFollowingOrSelf({
                hub: HUB,
                followerProfileId: processCollectParams.collectorProfileId,
                followedProfileId: processCollectParams.publicationCollectedProfileId
            });
        }

        uint256 endTimestamp = _dataByPublicationByProfile[processCollectParams.publicationCollectedProfileId][
            processCollectParams.publicationCollectedId
        ].endTimestamp;
        uint256 collectLimit = _dataByPublicationByProfile[processCollectParams.publicationCollectedProfileId][
            processCollectParams.publicationCollectedId
        ].collectLimit;

        if (collectLimit != 0 && collectsAfter > collectLimit) {
            revert Errors.MintLimitExceeded();
        }
        if (endTimestamp != 0 && block.timestamp > endTimestamp) {
            revert Errors.CollectExpired();
        }
    }

    /**
     * @dev Internal processing of a collect:
     *  1. Calculation of fees
     *  2. Validation that fees are what collector expected
     *  3. Transfer of fees to recipient(-s) and treasury
     *
     * @param processCollectParams Parameters of the collect
     */
    function _processCollect(ModuleTypes.ProcessCollectParams calldata processCollectParams) internal virtual {
        uint256 amount = calculateFee(processCollectParams);
        address currency = _dataByPublicationByProfile[processCollectParams.publicationCollectedProfileId][
            processCollectParams.publicationCollectedId
        ].currency;
        _validateDataIsExpected(processCollectParams.data, currency, amount);

        (address treasury, uint16 treasuryFee) = _treasuryData();
        uint256 treasuryAmount = (amount * treasuryFee) / BPS_MAX;

        if (treasuryAmount > 0) {
            IERC20(currency).safeTransferFrom(processCollectParams.transactionExecutor, treasury, treasuryAmount);
        }

        // Send amount after treasury cut, to all recipients
        _transferToRecipients(processCollectParams, currency, amount - treasuryAmount);
    }

    /**
     * @dev Internal processing of a collect with a referrals (if any).
     *
     * Same as _processCollect, but also includes transfer to referrals (if any):
     *  1. Calculation of fees
     *  2. Validation that fees are what collector expected
     *  3. Transfer of fees to treasury, referrals (if any) and recipients
     *
     * @param processCollectParams Parameters of the collect
     */
    function _processCollectWithReferral(
        ModuleTypes.ProcessCollectParams calldata processCollectParams
    ) internal virtual {
        uint256 amount = calculateFee(processCollectParams);
        address currency = _dataByPublicationByProfile[processCollectParams.publicationCollectedProfileId][
            processCollectParams.publicationCollectedId
        ].currency;

        _validateDataIsExpected(processCollectParams.data, currency, amount);

        (address treasury, uint16 treasuryFee) = _treasuryData();
        uint256 treasuryAmount = (amount * treasuryFee) / BPS_MAX;

        if (treasuryAmount > 0) {
            IERC20(currency).safeTransferFrom(processCollectParams.transactionExecutor, treasury, treasuryAmount);
        }

        uint256 amountAfterReferrals = _transferToReferrals(processCollectParams, currency, amount - treasuryAmount);

        _transferToRecipients(processCollectParams, currency, amountAfterReferrals);
    }

    /**
     * @dev Transfers the fee to recipient(-s)
     *
     * Override this to add additional functionality (e.g. multiple recipients)
     *
     * @param processCollectParams Parameters of the collect
     * @param currency Currency of the transaction
     * @param amount Amount to transfer to recipient(-s)
     */
    function _transferToRecipients(
        ModuleTypes.ProcessCollectParams calldata processCollectParams,
        address currency,
        uint256 amount
    ) internal virtual {
        address recipient = _dataByPublicationByProfile[processCollectParams.publicationCollectedProfileId][
            processCollectParams.publicationCollectedId
        ].recipient;

        if (amount > 0) {
            IERC20(currency).safeTransferFrom(processCollectParams.transactionExecutor, recipient, amount);
        }
    }

    /**
     * @dev Transfers the part of fee to referral(-s)
     *
     * Override this to add additional functionality (e.g. different amounts to different referrals, etc)
     *
     * @param processCollectParams Parameters of the collect
     * @param currency Currency of the transaction
     * @param amount Amount of the fee after subtracting the Treasury part.
     */
    function _transferToReferrals(
        ModuleTypes.ProcessCollectParams calldata processCollectParams,
        address currency,
        uint256 amount
    ) internal virtual returns (uint256) {
        uint256 referralFee = _dataByPublicationByProfile[processCollectParams.publicationCollectedProfileId][
            processCollectParams.publicationCollectedId
        ].referralFee;
        uint256 totalReferralsAmount;
        if (referralFee != 0) {
            // The reason we levy the referral fee on the adjusted amount is so that referral fees
            // don't bypass the treasury fee, in essence referrals pay their fair share to the treasury.
            totalReferralsAmount = (amount * referralFee) / BPS_MAX;
            uint256 numberOfReferrals = processCollectParams.referrerProfileIds.length;
            uint256 amountPerReferral = totalReferralsAmount / numberOfReferrals;
            if (amountPerReferral > 0) {
                uint256 i;
                while (i < numberOfReferrals) {
                    address referralRecipient = IERC721(HUB).ownerOf(processCollectParams.referrerProfileIds[i]);

                    // Send referral fee in ERC20 tokens
                    IERC20(currency).safeTransferFrom(
                        processCollectParams.transactionExecutor,
                        referralRecipient,
                        amountPerReferral
                    );
                    unchecked {
                        ++i;
                    }
                }
            }
        }
        return amount - totalReferralsAmount;
    }
}
