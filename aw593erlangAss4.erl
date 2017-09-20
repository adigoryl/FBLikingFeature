-module(aw593erlangAss4).
-compile([export_all]).

%	This processes takes care of randomly liking a post in random times between 0-5s
client(LS,Name)->
	sleep(),					%	sleeps between 0 - 5000 milliseconds
	RP = randNumber(5),			%	generates a random number between 0 and 5
	LS!{like, RP, self()}, 		%	1: sends to likeServer
	receive
		{likes, L} -> io:fwrite("~p likes post ~p (likes: ~p) ~n", [Name,RP,L]), client(LS,Name);
		{nopost} -> io:fwrite("~p post ~p doesn't exist ~n", [Name,RP]),  client(LS,Name)
	end.

%	Mainly interacts with the DB and intermmediate processes and manipulates the data fowards and back.
likeServer(Buff) ->
    receive
        {like, Post, Client} -> 					%	2: comes from client
            Buff!{like, Post, self()},				%	3: sends to buffer
				receive 
				{dataReply, Data} ->				%	6: comes from buffer
		        	case isPost(Data, Post) of
						true -> L = numOfLikes(Data, Post),
							Client!{likes, L+1},	%	8: sends to client
							likeServer(Buff);
						false -> Client!{nopost},
							 likeServer(Buff)
					end
		    	end
    end.

%	Quickly responds to the Client with updated likes and accordingly updates the data in the DB
buffer(UDB, Cache)->
	receive
		{like, Post, LS} ->							%	4: comes from likeServer
			LS!{dataReply, Cache},					%	5: sends to likeServer
			UDB!{updateDB, Post},					%	7: sends to updateDB
			UpdatedBuffer = likePost(Cache, Post), io:fwrite("Buffer: ~w~n", [UpdatedBuffer]),
			buffer(UDB, UpdatedBuffer)	
	end.

%	This process causes the 500 milliseconds delay between each update in the DB
updateDB(DB)->
	receive
		{updateDB, Post} ->
			DB!{updateLike, Post, self()},
			receive
				{updatingDone} ->
					timer:sleep(500),
					updateDB(DB)
			end
			
	end.

%	Updates the data
database(Data) ->
    receive
        {updateLike, Post, UDB} ->
			UDB!{updatingDone},
            Data2 = likePost(Data,Post),
			io:fwrite("DB: ~w~n", [Data2]),
            database(Data2)
    end.

%	Spawns the processes 
simulation()->
	L = [{5,0},{4,0},{3,0},{2,0},{1,0}],
	DB = spawn (?MODULE, database, [L]),
	UDB = spawn (?MODULE, updateDB,[DB]),
	Buff = spawn (?MODULE, buffer,[UDB,[L]]),
	LS = spawn (?MODULE, likeServer, [Buff]),
	spawn (?MODULE, client, [LS,"Adrian"]),
	spawn (?MODULE, client, [LS,"John"]),
	spawn (?MODULE, client, [LS,"Camilla"]),
	spawn (?MODULE, client, [LS,"Paul"]),
	spawn (?MODULE, client, [LS,"Bernie"]).

% 	---------------------------- 	 Q3 explanation 	  ----------------------------	%
%	To solve the problem of database only allowing to be accessed twice a second, 
%	I have created two intermediate processes, buffer and updateDB.
%	The buffer has it's own cache data, therefore is able to immediately respond to clients with the correct amount of 'like(s)'; 
%	by modifying and manipulating the cache. 
%	After the immediate response to the client, the buffer passes the 'likes' to the 'updateDB', 
%	where they are stacked and are awaiting to be allocated in the DB; one every 500 milliseconds.
%	This implementation has no effect on the clients as the buffer has it's cache data which updates and responds accordingly.



% 	---------------------------- 	 Q4 and Q5 as seperate 	  ----------------------------	%

%	This process chooses between liking or creating a new post.
client2(LS,Name)->
	sleep(),							%	sleeps for between 0 - 5000 milliseconds
	LikeOrPost = randNumber(1),			%	generates a random number betweeen 0 and 1.
	case LikeOrPost == 0 of				%	if 0, give it a like.
		true  -> LS!{like, self()},
				receive
					{likes, TotalLikes, LikedPostID} -> io:fwrite("~p likes post ~w (likes: ~w) ~n", [Name, LikedPostID, TotalLikes]), client2(LS,Name);
					{nopost} 						 -> io:fwrite("~p this post doesn't exist ~n", [Name]),  client2(LS,Name)
				end;
		
		false -> LS!{lock, self()}, 	%	if 1, create a new post.
				 LS!{addPost}, 	
				receive
					{unlock} 						 -> io:fwrite("New post by ~p ~n", [Name]),
					client2(LS,Name)
				end				 
	end.

%	This process mainly interacts with the DB or intermediate processes to retrieve, modify and pass on data.
likeServer2(DB) ->
    receive
        {like, Client} -> 
            DB!{like, self()},
            receive {dataReply, Data, Post} ->			%	retrieved current data from the db (before update)
                case isPost(Data, Post) of
                  true 	-> L = numOfLikes(Data, Post),
                          Client!{likes, L+1, Post},
                          likeServer2(DB);
                 
				  false -> Client!{nopost},
                           likeServer2(DB)
                end
            end;
		{lock, ParentClient} ->							
			serverInner(DB, ParentClient),				%	creats a stack/buffer
			likeServer2(DB)
    end.

%	This process is initialised by the likeServer2 and acts like a one off job.
serverInner(DB, ParentClient) ->
	receive
		{addPost} -> DB!{addPost, ParentClient}		 		
	end.

%	Acts like a database because stores and manipulates data
database2(Data) ->
    receive
        {like, Server} ->
			LikedPost = randNumber(count(Data)),				%	choses a random post to like
            Server!{dataReply, Data, LikedPost},
            ListWithNewLike = likePost(Data,LikedPost), 	
            database2(ListWithNewLike);
		
		{addPost, ParentClient} ->
			NewPostID = count(Data)+1,							%	creates a unique prosses ID
			ListWithNewPost = append([{NewPostID,0}], Data),	%	stacks the new post in front of the list
			ParentClient!{unlock},
			database2(ListWithNewPost)
    end.

%	Spawns the processes and provides appropiate arguments 
simulation2()->
	L = [{5,0},{4,0},{3,0},{2,0},{1,0}],
	DB = spawn (?MODULE, database2, [L]),
	LS = spawn (?MODULE, likeServer2, [DB]),
	spawn (?MODULE, client2, [LS,"Adrian"]),
	spawn (?MODULE, client2, [LS,"John"]),
	spawn (?MODULE, client2, [LS,"Camilla"]),
	spawn (?MODULE, client2, [LS,"Paul"]),
	spawn (?MODULE, client2, [LS,"Bernie"]).



% 	---------------------------- 	 SUB-METHODS 	----------------------------	%

%	Takes two lists and returns one.
append([],Ys) ->   Ys;
append([X|Xs],Ys) ->   [ X | append(Xs,Ys)].

%	Takes a list and return the number of elements.
count([])     -> 0;
count([_X|Xs]) -> 1 + count(Xs).

%	Sleeps a random time between 0 - 5000 milliseconds.
sleep() -> 
	timer:sleep(rand:uniform()*5000).

%	Returns a random number between 0 and 'PostsLength'.
randNumber(PostsLength)->
	round(rand:uniform()*PostsLength).

%	Calculated the amount of likes for the given posts in the given list.
numOfLikes([], _Post)                      -> 0;
numOfLikes([{Post, Likes} | _Posts], Post) -> Likes;
numOfLikes([_ | Posts], Post)              -> numOfLikes(Posts, Post).

%	Checks if the given post exists in the given list.
isPost([], _Post)                  -> false;
isPost([{Post, _} | _Posts], Post) -> true;
isPost([_ | Posts], Post)          -> isPost(Posts, Post).

%	Increments the given post
likePost([], _Post)                     -> [];
likePost([{Post, Likes} | Posts], Post) -> [{Post, Likes+1} | Posts];
likePost([P | Posts], Post)             -> [P | likePost(Posts, Post)].