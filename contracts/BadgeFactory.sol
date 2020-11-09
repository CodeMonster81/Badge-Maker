/// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.12;

/// @title Non-transferable Badges for Maker Ecosystem Activity, CDIP 18, 29
/// @author Nazzareno Massari @naszam
/// @notice BadgeFactory to manage Templates and activate Non-transferable MakerBadges by redeemers
/// @dev See https://github.com/makerdao/community/issues/537
/// @dev See https://github.com/makerdao/community/issues/721
/// @dev All function calls are currently implemented without side effects through TDD approach
/// @dev OpenZeppelin Library is used for secure contract development

/*
███    ███  █████  ██   ██ ███████ ██████ 
████  ████ ██   ██ ██  ██  ██      ██   ██ 
██ ████ ██ ███████ █████   █████   ██████  
██  ██  ██ ██   ██ ██  ██  ██      ██   ██ 
██      ██ ██   ██ ██   ██ ███████ ██   ██ 
*/



import "./BadgeRoles.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/cryptography/MerkleProof.sol";

interface MakerBadgesLike {
    function verify(uint256 templateId, address guy) external view returns (bool);
    function roots(uint256 templateId) external view returns (bytes32);
}

contract BadgeFactory is BadgeRoles, ERC721 {

    /// @dev Libraries
    using SafeMath for uint256;
    using Counters for Counters.Counter;
    using MerkleProof for bytes32[];

    MakerBadgesLike internal immutable maker;

    Counters.Counter private _templateIdTracker;

    struct BadgeTemplate {
        string name;
        string description;
        string image;
    }

    mapping (uint256 => BadgeTemplate) private templates;

    /// @dev Supplies of each badge template
    mapping(uint256 => uint256) private _templateQuantities;
    mapping(uint256 => uint256) private _tokenTemplates;

    mapping(bytes32 => uint256) public redeemed;

    /// @dev Events
    event NewTemplate(uint256 templateId, string name, string description, string image);
    event TemplateUpdated(uint256 templateId, string name, string description, string image);
    event BadgeActivated(address redeemer, uint256 templateId, string tokenURI);

    constructor(address maker_)
        public
        ERC721("MakerBadges", "MAKER")
    {
        _setBaseURI("https://badges.makerdao.com/token/");
        maker = MakerBadgesLike(maker_);
    }

    /// @notice Fallback function
    /// @dev Added not payable to revert transactions not matching any other function which send value
    fallback() external {
        revert();
    }

    /// @notice Set the baseURI
    /// @dev Update the baseURI specified in the constructor
    /// @param baseURI New baseURI
    /// @return True if the new baseURI is set
    function setBaseURI(string calldata baseURI) external returns (bool) {
        require(hasRole(ADMIN_ROLE, msg.sender), "MakerBadges: caller is not an admin");
        _setBaseURI(baseURI);
        return true;
    }

    /// @dev Templates

    /// @notice Create a new template
    /// @dev Access restricted to only Templaters
    /// @param name The name of the new template
    /// @param description A description of the new template
    /// @param image A filename of the new template
    /// @return True If the new Template is Created
    function createTemplate(string calldata name, string calldata description, string calldata image)
        external
        whenNotPaused
        returns (bool)
    {
        require(hasRole(TEMPLATER_ROLE, msg.sender), "BadgeFactory: caller is not a template owner");
        templates[_templateIdTracker.current()].name = name;
        templates[_templateIdTracker.current()].description = description;
        templates[_templateIdTracker.current()].image = image;

        _templateIdTracker.increment();
        uint256 _templateId = _templateIdTracker.current().sub(1);
        emit NewTemplate(_templateId, name, description, image);
        return true;
    }

    /// @notice Update a template
    /// @dev Access restricted to only Templaters
    /// @param templateId Template Id
    /// @param name The name of the template
    /// @param description The description of the template
    /// @param image The filename of the template
    /// @return True If the new Template is Updated
    function updateTemplate(uint256 templateId, string calldata name, string calldata description, string calldata image)
        external
        whenNotPaused
        returns (bool)
    {
        require(hasRole(TEMPLATER_ROLE, msg.sender), "BadgeFactory: caller is not a template owner");
        require(_templateIdTracker.current() > templateId, "BadgeFactory: no template with that id");
        templates[templateId].name = name;
        templates[templateId].description = description;
        templates[templateId].image = image;
        emit TemplateUpdated(templateId, name, description, image);
        return true;
    }

    /// @notice Getter function for templates
    /// @dev Check if templateId exists
    /// @param templateId Template Id of the template to return
    /// @return name description image Of the specified templateId
    function getTemplate(uint256 templateId)
        external
        view
        whenNotPaused
        returns (string memory name, string memory description, string memory image)
    {
        require(_templateIdTracker.current() > templateId, "BadgeFactory: no template with that id");
        return (templates[templateId].name, templates[templateId].description, templates[templateId].image);
    }

    /// @notice Getter function for templates count
    /// @dev Return lenght of template array
    /// @return count The current number of templates
    function getTemplatesCount() external view whenNotPaused returns (uint256 count) {
        return _templateIdTracker.current();
    }

    /// @dev Badges

    /// @notice Activate Badge by redeemers
    /// @dev Verify if the caller is a redeemer
    /// @param proof Merkle Proof
    /// @param templateId Template Id
    /// @param tokenURI Token URI
    /// @return True If the new Badge is Activated
    function activateBadge(bytes32[] calldata proof, uint256 templateId, string calldata tokenURI)
        external
        whenNotPaused
        returns (bool)
    {
        require(_templateIdTracker.current() > templateId, "BadgeFactory: no template with that id");
        require(redeemed[keccak256(abi.encodePacked(msg.sender, templateId))] == 0, "BadgeFactory: badge already activated!");
        require(
            maker.verify(templateId, msg.sender) || proof.verify(maker.roots(templateId), keccak256(abi.encodePacked(msg.sender))),
            "BadgeFactory: caller is not a redeemer"
        );

        /// @dev Increase the quantities
        _templateQuantities[templateId] = _templateQuantities[templateId].add(1);
        redeemed[keccak256(abi.encodePacked(msg.sender, templateId))] = 1;

        require(_mintWithTokenURI(msg.sender, templateId, tokenURI), "BadgeFactory: badge not minted");

        emit BadgeActivated(msg.sender, templateId, tokenURI);
        return true;
    }

    /// @notice Getter function for templateId associated with the tokenId
    /// @dev Check if the tokenId exists
    /// @param tokenId Token Id of the Badge
    /// @return redeemer Redeemer Address
    /// @return templateId Template Id
    function unpackTokenId(uint256 tokenId) external view whenNotPaused returns (address redeemer, uint256 templateId) {
        require(_exists(tokenId), "BadgeFactory: no token with that id");
        assembly {
            redeemer := shr(96,  and(tokenId, 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF000000000000000000000000))
            templateId := shr(88, and(tokenId, 0x0000000000000000000000000000000000000000FF0000000000000000000000))
        }
    }

    /// @notice Getter function for number of badges associated with templateId
    /// @dev Check if the template Id exists
    /// @param templateId Template Id
    /// @return Quantity of Badges associated with templateId
    function getBadgeTemplateQuantity(uint256 templateId) external view whenNotPaused returns (uint256) {
        require(_templateIdTracker.current() > templateId, "BadgeFactory: no template with that id");
        return _templateQuantities[templateId];
    }

    /// @notice ERC721 _transfer() Disabled
    /// @dev _transfer() has been overriden
    /// @dev reverts on transferFrom() and safeTransferFrom()
    function _transfer(address from, address to, uint256 tokenId) internal override {
        require(false, "BadgeFactory: badge transfer disabled");
        super._transfer(from, to, tokenId);
    }

    /// @notice Mint new token with tokenURI
    /// @dev Use an auto-generated tokenId
    /// @dev automatically concatenate baseURI with tokenURI via abi.encodePacked
    /// @param to owner of the new token
    /// @param tokenURI an <ipfs-hash>.json filename
    /// @return True if the new token is minted
    function _mintWithTokenURI(address to, uint256 templateId, string calldata tokenURI) private returns (bool) {
        bytes memory _tokenIdBytes = abi.encodePacked(to, templateId);
        uint _tokenId;
        assembly {
            _tokenId := mload(add(_tokenIdBytes, add(0x20, 0)))
        }
        _mint(to, _tokenId);
        _setTokenURI(_tokenId, tokenURI);
        return true;
    }
}
