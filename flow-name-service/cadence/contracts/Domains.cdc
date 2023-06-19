import NonFungibleToken from "./interfaces/NonFungibleToken.cdc"
import FungibleToken from "./interfaces/FungibleToken.cdc"
import FlowToken from "./tokens/FlowToken.cdc"



// "Domains" will implements contract interface "NonFungibleToken"
pub contract Domains: NonFungibleToken{

    // GLOBAL VARIABLES
    // hashname to address
    pub let owners: {String: Address}
    // hashname to string
    pub let expirationTimes: {String: UFix64}
    // A mapping for domain nameHash -> domain ID
    pub let nameHashToIDs: {String: UInt64}
    // counter to keep the no of domains minted
    pub var totalSupply: UInt64
    // define the list of characters which are forbidden to use in a domain name
    pub let forbiddenChars: String
    // duration for which the domain will be rented
    pub let minRentDuration: UFix64
    // define the maximum length of the domain name 
    pub let maxDomainLength: Int

    // GLOBAL FUNCTIONS
    // HELPER functions
    // check if the domain is available for sale
    pub fun isAvailable(nameHash: String): Bool{
        if(self.owners[nameHash]==nil){
            return true
        }
        return self.isExpired(nameHash: nameHash)
    }

    // Returns the expiry time of a domain
    pub fun getExpirationTime(nameHash: String): UFix64?{
        return self.expirationTimes[nameHash]
    }

    // checks if the domain is expired
    pub fun isExpired(nameHash: String): Bool{
        let currTime= getCurrentBlock().timestamp
        let expTime = self.expirationTimes[nameHash]

        if expTime != nil{
            return currTime >= expTime!
        }
        return false
    }

    // returns the eniter owners dictionary
    pub fun getAllOwners(): {String: Address}{
        return self.owners
    }

    // Returns the entire expirationTimes Dictionary
    pub fun getAllExpirationTimes(): {String: UFix64}{
        return self.expirationTimes
    }

    // update the owner of a domain
    access(account) fun updateOwner(nameHash: String, address: Address){
        self.owners[nameHash] = address
    }

    // update the expiration time of the domain
    // the account can access the code
    access(account) fun updateExpirationTime(nameHash: String, expTime: UFix64){
        self.expirationTimes[nameHash] = expTime
    }

    pub fun getAllNameHashToIds(): {String: UInt64}{
        return self.nameHashToIDs
    }

    access(account) fun updateNameHashToID(namehash: String, id: Uint64){
        self.nameHashToIDs[namehash] = id
    }


    // EVENTS
    pub event DomainBioChanged(nameHash: String, bio: String)
    pub event DomainAddressChanged(nameHash: String, address: Address)
    pub event DomainMinted(id: UInt64, name: String, nameHash: String, expiresAt: UFix64, receiver: Address)
    pub event DomainRenewed(id: UInt64, name: String, nameHash: String, expiresAt: UFix64, receiver: Address)

    // BEGIN:

    // struct to represent information about the FNS Domain
    pub struct DomainInfo{
        pub let id: UInt64
        pub let owner: Address
        pub let name: String
        pub let nameHash: String
        pub let expiresAt: UFix64
        pub let address: Address?
        pub let bio: String
        pub let createdAt: UFix64

        init(
            id: UInt64,
            owner: Address,
            name: String,
            nameHash: String,
            // * timestamp expressed in seconds
            expiresAt: UFix64,
            // * "?" represents an optional field, will be nil if not initialized
            address: Address?, 
            bio: String,
            createdAt: UFix64
        ){
            self.id = id
            self.owner = owner
            self.name = name
            self.nameHash = nameHash
            self.expiresAt = expiresAt
            self.address = address
            self.bio = bio
            self.createdAt = createdAt
        }

    }
    // public portion of NFT, made available to third parties
    pub resource interface DomainPublic {
        pub let id: UInt64
        pub let name: String
        pub let nameHash: String
        pub let createdAt: UFix64

        pub fun getBio(): String
        pub fun getAddress():Address?
        pub fun getDomainName():String
        pub fun getInfo(): DomainInfo
    }

    pub resource interface DomainPrivate {
        pub fun setBio(bio: String)
        pub fun setAddress(addr: Address)
    }


    // NFT - RESOURCE
    pub resource NFT: DomainPublic, DomainPrivate, NonFungibleToken.INFT {
        pub let id: UInt64
        pub let name: String
        pub let nameHash: String
        pub let createdAt: UFix64

        // Only the code written within this resource can access or modify this variable
        // similar to private in solidity
        access(self) var address: Address?
        access(self) var bio: String

        init(
            id: UInt64, name: String, nameHash: String
        ){
            self.id = id
            self.name = name
            self.nameHash = nameHash
            // OG way to get time on blockchain(timestamp of the current block on the network)
            self.createdAt = getCurrentBlock().timestamp
            self.address = nil
            self.bio = ""

            
        }
        pub fun getBio():String{
            return self.bio

        }

        pub fun getAddress(): Address?{
            return self.address
        }

        pub fun getDomainName(): String{
            return self.name.concat(".fns")
        }

        pub fun setBio(bio: String){

            // Just like the require statement in solidity
            pre{
                Domains.isExpired(nameHash: self.nameHash) == false : "Domain is expired"
            }
            self.bio = bio
            emit DomainBioChanged(nameHash: self.nameHash, bio: bio)

        }

        pub fun setAddress(addr: Address){

            pre{
                Domains.isExpired(nameHash: self.nameHash) == false : "domain is expired"

            }

            self.address = addr
            emit DomainAddressChanged(nameHash: self.nameHash, address: addr)

        }

        pub fun getInfo(): DomainInfo {
            let owner = Domains.owners[self.nameHash]!

            return DomainInfo(
                id:self.id,
                owner: owner,
                name: self.getDomainName(),
                nameHash: self.nameHash,
                expiresAt: Domains.expirationTimes[self.nameHash]!,
                address: self.address,
                bio: self.bio,
                createdAt: self.createdAt
            )
        }
    }

    // COLLECTION RESOURCE
    pub resource interface CollectionPublic {
        pub fun borrowDomain(id: UInt64): &{Domains.DomainPublic}

    }

    pub resource interface CollectionPrivate {
        access(account) fun mintDomain(name: String, nameHash: String, expiresAt: UFix64, receiver: Capability<&{NonFungibleToken.Receiver}>)
        pub fun borrowDomainPrivate(id: UInt64): &Domains.NFT
    }

    pub event Withdraw(id: UInt64, from: Address?)
    pub event Deposit(id: UInt64, to: Address?)

    pub resource Collection: CollectionPublic, CollectionPrivate, NonFungibleToken.Provider, NonFungibleToken.Receiver, NonFungibleToken.CollectionPublic {
        // mapping of tokenId to NFT resource
        pub var ownedNFTs: @{UInt64: NonFungibleToken.NFT}

        init(){

            self.ownedNFTs <- {}
        }

        pub fun withdraw(withdrawId: UInt64): @NonFungibleToken.NFT {
            let domain <- self.ownedNFTs.remove(key: withdrawId)
                ?? panic("NFT not found in collection!")
            
            emit Withdraw(id: domain.id, from: self.owner?.address)

            return <- domain
        }

        pub fun deposit(token: @NonFungibleToken.NFT){

            // typecast the generic NFT resource as a Damains.NFT resource
            let domain <- token as! @Domains.NFT
            let id = domain.id
            let nameHash = domain.nameHash

            if Domains.isExpired(nameHash: nameHash) {
                panic("Domain is expired!!")
            }

            Domains.updateOwner(nameHash: nameHash, address: self.owner?.address)

            let oldToken <- self.ownedNFTs[id] <- domain
            emit Deposit(id: id, to: self.owner?.address)

            destroy oldToken
        }

        pub fun getIds(): [UInt64]{
            // in a dictionary if only keys then it is a set

            return self.ownedNFTs.keys
        }
        
        pub fun borrowNFT(id: UInt64): &NonFungibleToken.NFT{
            return (&self.ownedNFTs[id] as &NonFungibleToken.NFT?)!
        }

        pub fun borrowDomain(id: UInt64): &{Domains.DomainPublic}{
            pre{
                self.ownedNFTs[id] != nil : "Domain does not exists" 
            }

            let token = (&self.ownedNFTs[id] as auth &NonFungibleToken.NFT?)!

            // type assesrtion operator, to explicitly convert a value to a specified type
            // if the cast fails at runtime, due to incompatible types, it will give runtime error
            return token as! &Domains.NFT
        }

        access(account) fun mintDomain(name: String, nameHash: String, expiresAt: UFix64, receiver: Capability<&{NonFungibleToken.Receiver}>){
            pre{
                Domains.isAvailable(nameHash: nameHash) : "Domain not available"
            }

            // "create" a resource
            let domain <- create Domain.NFT(
                    id: Domains.totalSupply, 
                    name: name, 
                    nameHash: nameHash
                )

            Domains.updateOwner(nameHash: nameHash, address: receiver.address)
            Domains.updateExpirationTime(nameHash: nameHash, expTime: expiresAt)

            Domains.updateNameHashToID(namehash: nameHash, id: domain.id)
            Domains.totalSupply = Domains.totalSupply + 1

            emit DomainMinted(id: domain.id, name: name, nameHash: nameHash, expiresAt: expiresAt, receiver: receiver.address)


            receiver.borrow()!.deposit(token: <- domain)
        }

        pub fun borrowDomainPrivate(id: UInt64): &Domains.NFT {
            pre{
                self.ownedNFTs[id] != nil: "Domain does not exist"
            }

            let ref = (&self.ownedNFTs[id] as auth &NonFungibleToken.NFT?)!

            return ref as! &Domains.NFT
        }

        // identical to destructor, destroys the resources!!
        destroy(){
            destroy self.ownedNFTs
        }
    }

    //* REGISTRAR RESOURCE */
    // interfaces provide Seperation of Concerns

    //* PUBLIC REGISTRAR INTERFACE */
    pub resource interface RegistrarPublic{
        // Unsigned fixed-point decimal type
        pub let minRentDuration: UFix64
        pub let maxDomainLength: Int
        // mapping: length of domain -> price of Domain
        pub let prices: {Int: UFix64}

        pub fun renewDomain(domain: &Domains.NFT, duration: UFix64, feeTokens: @FungibleToken.Vault)
        pub fun registerDomain(name: String, duration: UFix64, feeTokens: @FungibleToken.Vault, receiver: Capability<&{NonFungibleToken.Receiver}>)
        // returns the prices dictionary
        pub fun getPrices(): {Int : UFix64}
        pub fun getVaultBalance(): UFix64
    }

    //* PRIVATE REGISTRAR INTERFACE */
    pub resource interface RegistrarPrivate{
        pub fun updateRentVault(vault: @FungibleToken.Vault)
        pub fun withdrawVault(receiver: Capability<&{FungibleToken.Receiver}>, amount: UFix64)
        pub fun setPrices(key: Int, val: UFix64)
    }

}   