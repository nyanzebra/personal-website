+++
title = "Avoid Data-Loss in a Distributed Store"
date = 2026-02-05
[taxonomies]
tags = ["distributed-systems", "database"]
+++

## Intro
For work I had to solve an interesting problem I found: a situation where data-loss could occur due how stores were recovered during disaster recovery. Firstly, disaster recovery in this case means everything went down, nothing is available, there are no replicas available to use. Second, the data-loss had to do with picking the wrong (sometimes) replica to recover from and then use to bring back other replicas. Lastly it is worth calling out that this is for a custom store our team built into our product and not a real database, so this was a problem that needed to be solved manually.

<div class="section">
  <img src="/imgs/recovery1.jpg", alt="3 databases"/>
</div>

Looking at the above diagram, let's say all the databases die, which one do you pick to recover and use to bring up the others? Obviously we want the most up-to-date database to recover from... but how?

The mechanism to do this can be a sequence number. This is a monotonically increasing value that each database must track itself. Upon recovery, each database can communicate with an orchestrator or with all the others and effectively do [leader-election](https://en.wikipedia.org/wiki/Leader_election).

Some important parts though:
* The monotonically increasing value must be done as part of every commit (single transaction, all or nothing)
* The number to increase must be able to grow to a very large number, remember there could be millions of transactions!
* It is helpful to store this in metadata table of some sort, along with anything else one might need to use to recover, this allows for a single read at recovery time

This article is a bit shorter, but I think it is important to see that sometimes simple solutions are best even in complex distributed systems.
