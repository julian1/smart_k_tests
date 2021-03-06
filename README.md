
### refs

http://bitcoin.stackexchange.com/questions/28168/what-are-the-keys-used-in-the-blockchain-leveldb-ie-what-are-the-keyvalue-pair

https://bitcointalk.org/index.php?topic=977070.0

https://bitcoin.org/en/developer-reference#op-codes

https://en.bitcoin.it/wiki/Protocol_documentation

https://en.bitcoin.it/wiki/Base58Check_encoding

https://en.bitcoin.it/wiki/Script

https://en.bitcoin.it/wiki/Technical_background_of_Bitcoin_addresses

http://bitcoin.stackexchange.com/questions/12554/why-the-signature-is-always-65-13232-bytes-long

https://en.bitcoin.it/wiki/OP_CHECKSIG

https://bitcointalk.org/index.php?topic=29416.0

http://docs.camlcity.org/docs/godipkg/4.00/godi-zarith/doc/godi-zarith/html/Z.html

https://ocaml.janestreet.com/ocaml-core/109.13.00/doc/core/String.html

---
### deps

lwt, zarith



### TODO

  - should change to record all peer ip's and ports, but then add just ips to the exclude list
    so don't connect to the same node more than once.

  - IMPORTANT - for locator hashes - if don't increase the step beyond 500, then we'll always be 
    able to progress from a peer, on another chain.  

  - slow recursive db functions can be fixed with simple memoization tables.
    - so we don't actually need height, but maybe easier.

  - do we care about the leaves when constructing the getblocks request?. the point is that a client 
    can send what it knows about. if the block is valid, it will get added even if not the longest chain
    which is what we want.

  - rather than do read with fd, why not do with conn? and return conn...
      - then we don't have to compare fds
      - not sure.

  - change name connection to peer.

  - pending count is going to -1, something's not right...

  - IMPORTANT - Maybe do full connection cycle - eg. connect, version, verack, store to db in a single large job...
      - could put a timeout around the whole thing
      - the criteria is if we don't have to update state.
    rather than trying to bounce messages, and record details across different network events, ....
      - then we can get the version.agent etc...

  - IMPORTANT - also apply the above strategy to combine an inv request, and response against a peer?
      - would mean that don't require solicited calculations etc inv pending etc?
      - not sure when synched a new block can come from anywhere?
      - also it's up to a peer to not respond to an inv message if it doesn't have data.

  - should be storing ggg in the peer. eg. last_valid_block last_valid_inv ... just so we can
      monitor that the peer is responding.
      - this will get rid of the long list of stale fds.

  - if we don't have enough peers in the db, then the peer lookup query will be triggered on every event 

  - catch sig interupt - and clean shutdown, closing sockets

  - add peer client agent string to peer db table

  - move logger into session/state object, rather than be a free function, so that
    can partially apply at top level

  - check target difficulty

  - scrypt for lite and dogecoin
    - https://github.com/wg/scrypt/blob/master/src/main/java/com/lambdaworks/crypto/SCrypt.java

  - should change p2p, to always attempt connection when get new peer. and then drop on connection
    if have enough.

  - get micro-ecc working with native code library linking

  - store received blocks in queue, rather than blocking on the db writing, also automatic re-read

  - get full script evaluation working, not just sig-checking

  - lots of old filedescriptors in list, when they're probably not active.

  - fix our single entry packing of the inv request, which means we can't progress if the
      only leaf is an orphaned block.

  - issue - inventory tx cannot be cleared when block is produced, because a chainstate reoganisation could
    mean that block becomes orphaned.

  - get rid of caml case functions in message.ml

  - test for tx ecc checking. prev

  - finish wif

  - compute difficuly in relation to block time, so we can test against block difficulty
      - select * from _height where height % 2016 = 0;
      - we don't really want to store something that's a dynamic calc (like height or difficulty)
      - but we can't do expensive sql queries for each block ...

  - received time, different from stated block time.

  - the fact that getting previous txo's takes a while due to calculating the _main chain is ok. We can simply
    do one query and get all inputs for all txs in the block. o
      - but unconfirmed txos are an issue if receive every 1sec and it take .5 sec .
    - uggh creating the _main mat-view is taking 12 seconds for litecoin.

  - Consider using Zarith values instead of Int64 ...
  - refactor util and put app state in its own module

DONE

  - done - not null on main columns
  - done - organize with foreign keys first
  - done put unique constraint on tx hash
  - done add a mapping table between
  - done rename views to use prefix underscores
  - done - store the sigtype in signature
  - done move the tx pos, length into the tx_block structure, maybe also add blockdata id... no
  - done - get rid of blockdata? since it's one-to-one with block?
      - no - because allows non-null enforcement and might be faster
  - done record pos, len in output, starting from 0 in tx and check
  - done maybe same for input
  - done lookup the tx before insert to see if already have it
  - done - the blockdata i think should point at block. rather than block at blockdata.
      because for the first query hash there will be no blockdata.
  - done - and previous should be a separate table.

  - done - whether a block is mainnet, or orphaned or testnet is a dynamic property - now db.
  - done - move address test stuff in /test dir?
  - done - test for block header decode
  - done - we've got to get test code, extracted and working
  - done - decode difficulty, - can use either floating point, or z. float will be eaiser
  - done - merkle root / tree
  - done weight the p2p leave selection in favor of longest chain
      if random.int 4 < 3 pick... else pick next...
  - done we're getting tx's recorded twice, because they're in an orphaned block
      (should be fixed with _main and _tx views)
  - done - connect to ltc network
  - done - connect to doge network
  - done check tail calls of main functions
    - to check whether a tail is tail-call or not, you can use OCaml tools for
      that: compiling with the -annot option will produce an annotation file
      foo.annot (if your source was foo.ml)
  - done - altered to store height on block insertion
      - with 500k blocks - selecting _leaves is 200ms, selecting with height (_leaves2) 4700ms = 20x more expensive
      - it may make sense to record height - especially if we record difficulty
      - counter argument - getting list of blocks in main chain will always be slow due to recursive
        cte parent_id function

  - done - use the merkle check on blocks - to guanarantee the txs are right.

  - done - change process block (eg. check, add acc difficulty, height with) with process block
  - done peers in the db. just select at random like leaves. eg. if conns < 8, select random peer
    -this then gets the configuration out of p2p.

  - done - in p2p when getting new peers, filter according to what we are already connected to.
  - done - only add peer on receiving verack message,
  - done - netstat -tnp and strace + select() is showing a ton of conns in connect/write state?
      - maybe resolve by putting a timeout on connect? 
  - done seems ok. 
      lots of syn_sent - maybe because of pending counting, so it's always trying to open. 
  - done it doesn't look like we're getting more peers requests
      - getting lots of peers now.
  - done auxpow headers for dogecoin 


old todo
  - http/or cli interface to examine the read-only structures now, so
    it's not really necessary to dump state everytime.

  - simplify address storing in process_block not to use complicated prepared stmt
  - change var name 'x' to acc or something

  - maybe an module encapsulation of the String, Z, hex representation for hashes
    - with functions for Z or sha hashing or private/pub key, hex formatting  etc.
    - rather than converting everything around in code when needed.


----
issues

  - issue - could set initial peer via command line. if wanted.

  transaction malleability and removing items from mempool??? how?
    probably just record the block one, then the mempool one utxos will be spent
----
   - note that tx data may be stored twice in two forked blocks. we get it correctly...
  - meaning it may appear more than once...

  - ok, there's an issue that tx data might be in block, or somewhere else
    makes it har

---
  change name process_block to store_block ?

  - IMPORTANT should move the transaction isolation begin and commit outside the process block
    so that if want to do other actions - like check if block has been inserted in the same
    tx we can.
      - not sure - what about exceptions and rollback

