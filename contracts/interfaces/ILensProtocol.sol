// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0;

import {Types} from 'contracts/libraries/constants/Types.sol';

/**
 * @title ILensProtocol
 * @author Lens Protocol
 *
 * @notice This is the interface for Lens Protocol's core functions. It contains all the entry points for performing
 * social operations.
 */
interface ILensProtocol {
    /**
     * @notice Creates a profile with the specified parameters, minting a Profile NFT to the given recipient.
     * @custom:permissions Any whitelisted profile creator.
     *
     * @param createProfileParams A CreateProfileParams struct containing the needed params.
     */
    function createProfile(Types.CreateProfileParams calldata createProfileParams) external returns (uint256);

    /**
     * @notice Sets the metadata URI for the given profile.
     * @custom:permissions Profile Owner or Delegated Executor.
     *
     * @param profileId The token ID of the profile to set the metadata URI for.
     * @param metadataURI The metadata URI to set for the given profile.
     */
    function setProfileMetadataURI(uint256 profileId, string calldata metadataURI) external;

    /**
     * @custom:meta-tx setProfileMetadataURI.
     */
    function setProfileMetadataURIWithSig(
        uint256 profileId,
        string calldata metadataURI,
        Types.EIP712Signature calldata signature
    ) external;

    /**
     * @notice Sets the follow module for the given profile.
     * @custom:permissions Profile Owner or Delegated Executor.
     *
     * @param profileId The token ID of the profile to set the follow module for.
     * @param followModule The follow module to set for the given profile, must be whitelisted.
     * @param followModuleInitData The data to be passed to the follow module for initialization.
     */
    function setFollowModule(uint256 profileId, address followModule, bytes calldata followModuleInitData) external;

    /**
     * @custom:meta-tx setFollowModule.
     */
    function setFollowModuleWithSig(
        uint256 profileId,
        address followModule,
        bytes calldata followModuleInitData,
        Types.EIP712Signature calldata signature
    ) external;

    /**
     * @notice Changes the delegated executors configuration for the given profile. It allows setting the approvals for
     * delegated executors in the specified configuration, as well as switching to it.
     * @custom:permissions Profile Owner.
     *
     * @param delegatorProfileId The ID of the profile to which the delegated executor is being changed for.
     * @param delegatedExecutors The array of delegated executors to set the approval for.
     * @param approvals The array of booleans indicating the corresponding executor's new approval status.
     * @param configNumber The number of the configuration where the executor approval state is being set.
     * @param switchToGivenConfig A boolean indicating if the configuration must be switched to the one with the given
     * number.
     */
    function changeDelegatedExecutorsConfig(
        uint256 delegatorProfileId,
        address[] calldata delegatedExecutors,
        bool[] calldata approvals,
        uint64 configNumber,
        bool switchToGivenConfig
    ) external;

    /**
     * @notice Changes the delegated executors configuration for the given profile under the current configuration.
     * @custom:permissions Profile Owner.
     *
     * @param delegatorProfileId The ID of the profile to which the delegated executor is being changed for.
     * @param delegatedExecutors The array of delegated executors to set the approval for.
     * @param approvals The array of booleans indicating the corresponding executor's new approval status.
     */
    function changeDelegatedExecutorsConfig(
        uint256 delegatorProfileId,
        address[] calldata delegatedExecutors,
        bool[] calldata approvals
    ) external;

    /**
     * @custom:meta-tx changeDelegatedExecutorsConfig.
     */
    function changeDelegatedExecutorsConfigWithSig(
        uint256 delegatorProfileId,
        address[] calldata delegatedExecutors,
        bool[] calldata approvals,
        uint64 configNumber,
        bool switchToGivenConfig,
        Types.EIP712Signature calldata signature
    ) external;

    /**
     * @notice Publishes a post.
     * Post is the most basic publication type, and can be used to publish any kind of content.
     * Posts can have these types of modules initialized:
     *  - Action modules: any number of publication actions (e.g. collect, tip, etc.)
     *  - Reference module: a module handling the rules when referencing this post (e.g. token-gated comments)
     * @custom:permissions Profile Owner or Delegated Executor.
     *
     * @param postParams A PostParams struct containing the needed parameters.
     *
     * @return uint256 An integer representing the post's publication ID.
     */
    function post(Types.PostParams calldata postParams) external returns (uint256);

    /**
     * @custom:meta-tx post.
     */
    function postWithSig(
        Types.PostParams calldata postParams,
        Types.EIP712Signature calldata signature
    ) external returns (uint256);

    /**
     * @notice Publishes a comment on the given publication.
     * Comment is a type of reference publication that points to another publication.
     * Comments can have these types of modules initialized:
     *  - Action modules: any number of publication actions (e.g. collect, tip, etc.)
     *  - Reference module: a module handling the rules when referencing this comment (e.g. token-gated mirrors)
     * Comments can have referrers (e.g. publications or profiles that helped to discover the pointed publication).
     * @custom:permissions Profile Owner or Delegated Executor.
     *
     * @param commentParams A CommentParams struct containing the needed parameters.
     *
     * @return uint256 An integer representing the comment's publication ID.
     */
    function comment(Types.CommentParams calldata commentParams) external returns (uint256);

    /**
     * @custom:meta-tx comment.
     */
    function commentWithSig(
        Types.CommentParams calldata commentParams,
        Types.EIP712Signature calldata signature
    ) external returns (uint256);

    /**
     * @notice Publishes a mirror of the given publication.
     * Mirror is a type of reference publication that points to another publication but doesn't have content.
     * Mirrors don't have any modules initialized.
     * Mirrors can have referrers (e.g. publications or profiles that allowed to discover the pointed publication).
     * You cannot mirror a mirror, comment on a mirror, or quote a mirror.
     * @custom:permissions Profile Owner or Delegated Executor.
     *
     * @param mirrorParams A MirrorParams struct containing the necessary parameters.
     *
     * @return uint256 An integer representing the mirror's publication ID.
     */
    function mirror(Types.MirrorParams calldata mirrorParams) external returns (uint256);

    /**
     * @custom:meta-tx mirror.
     */
    function mirrorWithSig(
        Types.MirrorParams calldata mirrorParams,
        Types.EIP712Signature calldata signature
    ) external returns (uint256);

    /**
     * @notice Publishes a quote of the given publication.
     * Quote is a type of reference publication similar to mirror, but it has content and modules.
     * Quotes can have these types of modules initialized:
     *  - Action modules: any number of publication actions (e.g. collect, tip, etc.)
     *  - Reference module: a module handling the rules when referencing this quote (e.g. token-gated comments on quote)
     * Quotes can have referrers (e.g. publications or profiles that allowed to discover the pointed publication).
     * Unlike mirrors, you can mirror a quote, comment on a quote, or quote a quote.
     * @custom:permissions Profile Owner or Delegated Executor.
     *
     * @param quoteParams A QuoteParams struct containing the needed parameters.
     *
     * @return uint256 An integer representing the quote's publication ID.
     */
    function quote(Types.QuoteParams calldata quoteParams) external returns (uint256);

    /**
     * @custom:meta-tx quote.
     */
    function quoteWithSig(
        Types.QuoteParams calldata quoteParams,
        Types.EIP712Signature calldata signature
    ) external returns (uint256);

    /**
     * @notice Follows given profiles, executing each profile's follow module logic (if any).
     * @custom:permissions Profile Owner or Delegated Executor.
     *
     * @dev Both the `idsOfProfilesToFollow`, `followTokenIds`, and `datas` arrays must be of the same length,
     * regardless if the profiles do not have a follow module set.
     *
     * @param followerProfileId The ID of the profile the follows are being executed for.
     * @param idsOfProfilesToFollow The array of IDs of profiles to follow.
     * @param followTokenIds The array of follow token IDs to use for each follow (0 if you don't own a follow token).
     * @param datas The arbitrary data array to pass to the follow module for each profile if needed.
     *
     * @return uint256[] An array of follow token IDs representing the follow tokens created for each follow.
     */
    function follow(
        uint256 followerProfileId,
        uint256[] calldata idsOfProfilesToFollow,
        uint256[] calldata followTokenIds,
        bytes[] calldata datas
    ) external returns (uint256[] memory);

    /**
     * @custom:meta-tx follow.
     */
    function followWithSig(
        uint256 followerProfileId,
        uint256[] calldata idsOfProfilesToFollow,
        uint256[] calldata followTokenIds,
        bytes[] calldata datas,
        Types.EIP712Signature calldata signature
    ) external returns (uint256[] memory);

    /**
     * @notice Unfollows given profiles.
     * @custom:permissions Profile Owner or Delegated Executor.
     *
     * @param unfollowerProfileId The ID of the profile the unfollows are being executed for.
     * @param idsOfProfilesToUnfollow The array of IDs of profiles to unfollow.
     */
    function unfollow(uint256 unfollowerProfileId, uint256[] calldata idsOfProfilesToUnfollow) external;

    /**
     * @custom:meta-tx unfollow.
     */
    function unfollowWithSig(
        uint256 unfollowerProfileId,
        uint256[] calldata idsOfProfilesToUnfollow,
        Types.EIP712Signature calldata signature
    ) external;

    /**
     * @notice Sets the block status for the given profiles. Changing a profile's block status to `true` (i.e. blocked),
     * when will also force them to unfollow.
     * Blocked profiles cannot perform any actions with the profile that blocked them: they cannot comment or mirror
     * their publications, they cannot follow them, they cannot collect, tip them, etc.
     * @custom:permissions Profile Owner or Delegated Executor.
     *
     * @dev Both the `idsOfProfilesToSetBlockStatus` and `blockStatus` arrays must be of the same length.
     *
     * @param byProfileId The ID of the profile that is blocking/unblocking somebody.
     * @param idsOfProfilesToSetBlockStatus The array of IDs of profiles to set block status.
     * @param blockStatus The array of block statuses to use for each (true is blocked).
     */
    function setBlockStatus(
        uint256 byProfileId,
        uint256[] calldata idsOfProfilesToSetBlockStatus,
        bool[] calldata blockStatus
    ) external;

    /**
     * @custom:meta-tx setBlockStatus.
     */
    function setBlockStatusWithSig(
        uint256 byProfileId,
        uint256[] calldata idsOfProfilesToSetBlockStatus,
        bool[] calldata blockStatus,
        Types.EIP712Signature calldata signature
    ) external;

    /**
     * @notice Collects a given publication via signature with the specified parameters.
     * Collect can have referrers (e.g. publications or profiles that allowed to discover the pointed publication).
     * @custom:permissions Collector Profile Owner or its Delegated Executor.
     * @custom:pending-deprecation Collect modules were replaced by PublicationAction Collect modules in V2. This method
     * is left here for backwards compatibility with posts made in V1 that had Collect modules.
     *
     * @param collectParams A CollectParams struct containing the parameters.
     *
     * @return uint256 An integer representing the minted token ID.
     */
    function collectLegacy(Types.LegacyCollectParams calldata collectParams) external returns (uint256);

    /**
     * @custom:meta-tx collect.
     * @custom:pending-deprecation
     */
    function collectLegacyWithSig(
        Types.LegacyCollectParams calldata collectParams,
        Types.EIP712Signature calldata signature
    ) external returns (uint256);

    /**
     * @notice Acts on a given publication with the specified parameters.
     * You can act on a publication except a mirror (if it has at least one action module initialized).
     * Actions can have referrers (e.g. publications or profiles that allowed to discover the pointed publication).
     * @custom:permissions Actor Profile Owner or its Delegated Executor.
     *
     * @param publicationActionParams A PublicationActionParams struct containing the parameters.
     *
     * @return bytes Arbitrary data the action module returns.
     */
    function act(Types.PublicationActionParams calldata publicationActionParams) external returns (bytes memory);

    /**
     * @custom:meta-tx act.
     */
    function actWithSig(
        Types.PublicationActionParams calldata publicationActionParams,
        Types.EIP712Signature calldata signature
    ) external returns (bytes memory);

    /**
     * @dev This function is used to invalidate signatures by incrementing the nonce of the signer.
     * @param increment The amount to increment the nonce by (max 255).
     */
    function incrementNonce(uint8 increment) external;

    /////////////////////////////////
    ///       VIEW FUNCTIONS      ///
    /////////////////////////////////

    /**
     * @notice Returns whether or not `followerProfileId` is following `followedProfileId`.
     *
     * @param followerProfileId The ID of the profile whose following state should be queried.
     * @param followedProfileId The ID of the profile whose followed state should be queried.
     *
     * @return bool True if `followerProfileId` is following `followedProfileId`, false otherwise.
     */
    function isFollowing(uint256 followerProfileId, uint256 followedProfileId) external view returns (bool);

    /**
     * @notice Returns whether the given address is approved as delegated executor, in the configuration with the given
     * number, to act on behalf of the given profile.
     *
     * @param delegatorProfileId The ID of the profile to check the delegated executor approval for.
     * @param delegatedExecutor The address to query the delegated executor approval for.
     * @param configNumber The number of the configuration where the executor approval state is being queried.
     *
     * @return bool True if the address is approved as a delegated executor to act on behalf of the profile in the
     * given configuration, false otherwise.
     */
    function isDelegatedExecutorApproved(
        uint256 delegatorProfileId,
        address delegatedExecutor,
        uint64 configNumber
    ) external view returns (bool);

    /**
     * @notice Returns whether the given address is approved as delegated executor, in the current configuration, to act
     * on behalf of the given profile.
     *
     * @param delegatorProfileId The ID of the profile to check the delegated executor approval for.
     * @param delegatedExecutor The address to query the delegated executor approval for.
     *
     * @return bool True if the address is approved as a delegated executor to act on behalf of the profile in the
     * current configuration, false otherwise.
     */
    function isDelegatedExecutorApproved(
        uint256 delegatorProfileId,
        address delegatedExecutor
    ) external view returns (bool);

    /**
     * @notice Returns the current delegated executor config number for the given profile.
     *
     * @param delegatorProfileId The ID of the profile from which the delegated executors config number is being queried
     *
     * @return uint256 The current delegated executor configuration number.
     */
    function getDelegatedExecutorsConfigNumber(uint256 delegatorProfileId) external view returns (uint64);

    /**
     * @notice Returns the previous used delegated executor config number for the given profile.
     *
     * @param delegatorProfileId The ID of the profile from which the delegated executors' previous configuration number
     * set is being queried.
     *
     * @return uint256 The delegated executor configuration number previously set. It will coincide with the current
     * configuration set if it was never switched from the default one.
     */
    function getDelegatedExecutorsPrevConfigNumber(uint256 delegatorProfileId) external view returns (uint64);

    /**
     * @notice Returns the maximum delegated executor config number for the given profile.
     * This is the maximum config number that was ever used by this profile.
     * When creating a new clean configuration, you can only use a number that is maxConfigNumber + 1.
     *
     * @param delegatorProfileId The ID of the profile from which the delegated executors' maximum configuration number
     * set is being queried.
     *
     * @return uint256 The delegated executor maximum configuration number set.
     */
    function getDelegatedExecutorsMaxConfigNumberSet(uint256 delegatorProfileId) external view returns (uint64);

    /**
     * @notice Returns whether `profileId` is blocked by `byProfileId`.
     * See setBlockStatus() for more information on how blocking works on the platform.
     *
     * @param profileId The ID of the profile whose blocked status should be queried.
     * @param byProfileId The ID of the profile whose blocker status should be queried.
     *
     * @return bool True if `profileId` is blocked by `byProfileId`, false otherwise.
     */
    function isBlocked(uint256 profileId, uint256 byProfileId) external view returns (bool);

    /**
     * @notice Returns the URI associated with a given publication.
     * This is used to store the publication's metadata, e.g.: content, images, etc.
     *
     * @param profileId The token ID of the profile that published the publication to query.
     * @param pubId The publication ID of the publication to query.
     *
     * @return string The URI associated with a given publication.
     */
    function getContentURI(uint256 profileId, uint256 pubId) external view returns (string memory);

    /**
     * @notice Returns the full profile struct associated with a given profile token ID.
     *
     * @param profileId The token ID of the profile to query.
     *
     * @return Profile The profile struct of the given profile.
     */
    function getProfile(uint256 profileId) external view returns (Types.Profile memory);

    /**
     * @notice Returns the full publication struct for a given publication.
     *
     * @param profileId The token ID of the profile that published the publication to query.
     * @param pubId The publication ID of the publication to query.
     *
     * @return Publication The publication struct associated with the queried publication.
     */
    function getPublication(uint256 profileId, uint256 pubId) external view returns (Types.PublicationMemory memory);

    /**
     * @notice Returns the type of a given publication.
     * The type can be one of the following (see PublicationType enum):
     * - Nonexistent
     * - Post
     * - Comment
     * - Mirror
     * - Quote
     *
     * @param profileId The token ID of the profile that published the publication to query.
     * @param pubId The publication ID of the publication to query.
     *
     * @return PublicationType The publication type of the queried publication.
     */
    function getPublicationType(uint256 profileId, uint256 pubId) external view returns (Types.PublicationType);

    /**
     * @notice Returns whether a given Action Module is enabled for a given publication.
     *
     * @param profileId The token ID of the profile that published the publication to query.
     * @param pubId The publication ID of the publication to query.
     * @param module The address of the Action Module to query.
     *
     * @return bool True if the Action Module is enabled for the queried publication, false if not.
     */
    function isActionModuleEnabledInPublication(
        uint256 profileId,
        uint256 pubId,
        address module
    ) external view returns (bool);
}
