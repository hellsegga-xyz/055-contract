// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./ERC721A.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./SSTORE2.sol";

import {MintVerifier} from "./MintVerifier.sol";
import {RevealVerifier} from "./RevealVerifier.sol";
import {EBMP} from "./EBMP.sol";
import {Base64} from "./Base64.sol";

struct ZeroKnowledgePrivateData {
    uint256[2] a;
    uint256[4] b;
    uint256[2] c;
}

struct MintData {
    // Zero Knowledge Proof parameter for private data
    ZeroKnowledgePrivateData privateData;
    // Token's public data, as specified per mint circuit
    uint256[24] publicData;
}

struct RevealData {
    // Zero Knowledge Proof parameter for private data
    ZeroKnowledgePrivateData privateData;
    // Token's public data, as specified per reveal circuit
    uint256[293] publicData;
}

contract Artifact055 is Ownable, ERC721A, ReentrancyGuard {

    // Specify a start price
    uint256 public currentPrice;

    // zk-SNARK Verifier for mint proof
    address public immutable mintVerifier;

    // zk-SNARK Verifier for reveal proof
    address public immutable revealVerifier;

    // Mapping from tokenId to thumbnail image
    address[] private thumbnail;

    // Mapping from tokenId to original image, encrypted or not
    address[] private content;

    // Mapping from tokenId to the hash of owner and minter's pubKeys & content hash
    mapping(uint256 => bytes32) public pubKeyContentHash;

    // Is content hash unique
    mapping(uint256 => bool) private _contentHashes;

    // Whether the image represented by contentHash is encrypted on chain
    mapping(uint256 => bool) public encrypted;

    // Mapping from uniqueId (stored on backend) to tokenId
    mapping(uint256 => uint256) public uniqueIdMapping;


    // Event for backend to know that a new NFT is minted
    event Mint(
        address indexed creator,
        uint256 indexed uniqueId,
        uint256 indexed tokenId
    );

    event Revealed(
        uint256 indexed tokenId
    );

    constructor(
        uint256 maxBatchSize_,
        uint256 collectionSize_,
        uint256 startPrice_,
        address mintVerifier_,
        address revealVerifier_
    ) ERC721A("055", "055", maxBatchSize_, collectionSize_) {
        currentPrice = startPrice_;
        mintVerifier = mintVerifier_;
        revealVerifier = revealVerifier_;
    }

    modifier callerIsUser() {
        require(tx.origin == msg.sender, "The caller is another contract");
        _;
    }

    function reveal(uint256 tokenId, RevealData calldata data)
        external
        callerIsUser
        nonReentrant
    {
        require(_exists(tokenId), "nonexistent token");

        bytes32 pkeychash = keccak256(
            abi.encodePacked(
                data.publicData[0],
                data.publicData[1],
                data.publicData[2],
                data.publicData[3],
                data.publicData[4]
            )
        );

        require(encrypted[tokenId], "token already revealed");
        require(ownershipOf(tokenId).addr == msg.sender, "caller not owner");
        require(
            pkeychash == pubKeyContentHash[tokenId],
            "public key hash does not match"
        );
        require(
            RevealVerifier(revealVerifier).verifyProof(
                data.privateData.a,
                data.privateData.b,
                data.privateData.c,
                data.publicData
            ),
            "invalid reveal proof"
        );

        uint256[288] memory contentData;
        for (uint256 i = 5; i < 5 + 288; i++) {
            contentData[i - 5] = data.publicData[i];
        }

        content[tokenId] = SSTORE2.write(abi.encodePacked(contentData));

        encrypted[tokenId] = false;
        emit Revealed(tokenId);
    }

    function checkMintProof(MintData calldata data)
        external
        view
        returns (bool)
    {
        return
            MintVerifier(mintVerifier).verifyProof(
                data.privateData.a,
                data.privateData.b,
                data.privateData.c,
                data.publicData
            );
    }

    function _mint(address creator, MintData calldata data) internal {
        address recipient = address(uint160(data.publicData[0]));
        uint256 contentHash = data.publicData[1];

        require(
            _contentHashes[contentHash] == false,
            "a token has already been created with this content hash"
        );
        require(
            MintVerifier(mintVerifier).verifyProof(
                data.privateData.a,
                data.privateData.b,
                data.privateData.c,
                data.publicData
            ),
            "invalid mint proof"
        );

        uint256 tokenId = currentIndex;
        _contentHashes[contentHash] = true;

        pubKeyContentHash[tokenId] = keccak256(
            abi.encodePacked(
                contentHash,
                data.publicData[4],
                data.publicData[5],
                data.publicData[2],
                data.publicData[3]
            )
        );

        uint256[18] memory thumbnailData;
        for (uint256 i = 6; i < 6 + 18; i++) {
            thumbnailData[i - 6] = data.publicData[i];
        }

        thumbnail.push(SSTORE2.write(abi.encodePacked(thumbnailData)));
        content.push(address(0));

        encrypted[tokenId] = true;

        // Server's public key is stored in publicData[4] and publicData[5]
        // The x-coord (publicData[4]) will be used as the uniqueId
        // Set the mapping between uniqueId and tokenId
        // Undefined mapping returns 0, which could be a problem
        uniqueIdMapping[tokenId] = data.publicData[4];

        _safeMint(recipient, 1);

        // Emit an event to let the backend know a NFT has been minted
        emit Mint(creator, data.publicData[4], tokenId);
    }

    function publicMint(MintData calldata data)
        external
        payable
        callerIsUser
        nonReentrant
    {
        require(totalSupply() + 1 <= collectionSize, "reached max supply");
        require(msg.value >= currentPrice, "Need to send more ETH.");
        _mint(msg.sender, data);
        refundIfOver(currentPrice);
    }

    function refundIfOver(uint256 price) private {
        require(msg.value >= price, "Need to send more ETH.");
        if (msg.value > price) {
            payable(msg.sender).transfer(msg.value - price);
        }
    }

    string private header =
        '<svg image-rendering="pixelated" preserveAspectRatio="xMinYMin meet" viewBox="0 0 350 350" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" > <image width="100%" height="100%" xlink:href="data:image/bmp;base64,';
    string private footer = '" /> </svg>';

    function _renderThumbnail(uint256 tokenId)
        internal
        view
        virtual
        returns (string memory)
    {
        bytes memory rawData = SSTORE2.read(thumbnail[tokenId]);
        uint8[] memory image = new uint8[](432);
        for (uint256 i = 0; i < 6; i++) {
            for (uint256 c = 0; c < 3; c++) {
                for (uint256 k = 0; k < 24; k++) {
                    image[(i * 24 + k) * 3 + (2 - c)] = uint8(
                        rawData[(i * 3 + c) * 32 + 31 - k]
                    );
                }
            }
        }
        string memory enc = EBMP.encodeBMP(image, 12, 12, 3);

        enc = string(abi.encodePacked(header, enc, footer));

        return enc;
    }

    function _renderOriginal(uint256 tokenId)
        internal
        view
        virtual
        returns (string memory)
    {
        bytes memory rawData = SSTORE2.read(content[tokenId]);
        uint8[] memory image = new uint8[](6912);
        for (uint256 i = 0; i < 2; i++) {
            for (uint256 j = 0; j < 48; j++) {
                for (uint256 c = 0; c < 3; c++) {
                    for (uint256 k = 0; k < 24; k++) {
                        image[((i * 24 + k) * 48 + j) * 3 + (2 - c)] = uint8(
                            rawData[((i * 48 + j) * 3 + c) * 32 + 31 - k]
                        );
                    }
                }
            }
        }
        string memory enc = EBMP.encodeBMP(image, 48, 48, 3);

        enc = string(abi.encodePacked(header, enc, footer));

        return enc;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );
        string memory img;
        string memory encrypt;
        if (encrypted[tokenId]) {
            img = _renderThumbnail(tokenId);
            encrypt = "true";
        } else {
            img = _renderOriginal(tokenId);
            encrypt = "false";
        }

        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "', Strings.toString(tokenId) ,'", "image": "data:image/svg+xml;base64,',
                        Base64.encode(bytes(img)), '", "uniqueId":"', Strings.toString(uniqueIdMapping[tokenId]),
                        '", "encrypted": ', encrypt ,
                        '}'
                    )
                )
            )
        );
        string memory output = string(
            abi.encodePacked("data:application/json;base64,", json)
        );

        return output;
    }

    function withdrawMoney() external onlyOwner nonReentrant {
        (bool success, ) = msg.sender.call{value: address(this).balance}("");
        require(success, "Transfer failed.");
    }

    function setOwnersExplicit(uint256 quantity)
        external
        onlyOwner
        nonReentrant
    {
        _setOwnersExplicit(quantity);
    }

    function numberMinted(address owner) public view returns (uint256) {
        return _numberMinted(owner);
    }

    function getOwnershipData(uint256 tokenId)
        external
        view
        returns (TokenOwnership memory)
    {
        return ownershipOf(tokenId);
    }

}
