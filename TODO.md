- simplify example ContentView, remove router, worker, it is enough to have some leak inside model, maybe self holding or osmething in closure, sth classic
- i see that artifacts/xctest-memory-diagnostics is 21 MB because of screenshots inside xcresult
- xctrace artifacts were i guess ~19MB because of trace file full of memory recordings


- in /Users/omac/Code/personal-web-blogpost-related/xctrace-leak-testing/tooling i would rename each folder to similar name as are each of two ui tests in app


- instead of run-ios.sh and subscript, make just one shell script and organize each section and helper into functions so it is more readable, if possible i would like to have on top some main function that will show all flow of the script right on top of file, it can be called on end of file, but declaration could be up for readers, but if not possible due to how definitions in script work, then not needed