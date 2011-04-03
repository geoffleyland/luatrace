LUA= $(shell echo `which lua`)
LUA_BINDIR= $(shell echo `dirname $(LUA)`)
LUA_PREFIX= $(shell echo `dirname $(LUA_BINDIR)`)
LUA_SHAREDIR=$(LUA_PREFIX)/share/lua/5.1
LUA_LIBDIR=$(LUA_PREFIX)/lib/lua/5.1
LUA_INCDIR=$(LUA_PREFIX)/include

CC=cc
CFLAGS=-O3 -fPIC -wall

# Guess a platform
UNAME=$(shell uname -s)
ifneq (,$(findstring Darwin,$(UNAME)))
  # OS X
  CFLAGS:=$(CFLAGS) -arch i686 -arch x86_64
  SHARED=-bundle -undefined dynamic_lookup
  LIBS=
  SO_SUFFIX=so
else
  # Linux
  SHARED=-shared -llua
  LIBS=-lcstring
  SO_SUFFIX=so
endif

lua/luatrace/c_hook.$(SO_SUFFIX): c/c_hook.c
	$(CC) $(CFLAGS) $(SHARED) $^ -o $@ $(LIBS) -I$(LUA_INCDIR)

install: lua/luatrace/c_hook.$(SO_SUFFIX)
	mkdir -p $(LUA_SHAREDIR)/luatrace
	mkdir -p $(LUA_LIBDIR)/luatrace
	cp lua/luatrace.lua $(LUA_SHAREDIR)
	cp lua/uatrace.lua $(LUA_SHAREDIR)
	cp lua/luatrace/*.lua $(LUA_SHAREDIR)/luatrace
	-cp lua/luatrace/c_hook.so $(LUA_LIBDIR)/luatrace
	cp sh/luaprofile $(LUA_BINDIR)
	chmod +x $(LUA_BINDIR)/luaprofile

uninstall: 
	rm -f $(LUA_SHAREDIR)/luatrace.lua
	rm -f $(LUA_SHAREDIR)/uatrace.lua
	rm -rf $(LUA_SHAREDIR)/luatrace
	-rm rf $(LUA_LIBDIR)/luatrace
	rm -f $(LUA_BINDIR)/luaprofile

clean:
	rm -f lua/luatrace/c_hook.so
	find . -name "trace-out.txt" -delete

