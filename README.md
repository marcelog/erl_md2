# erl_md2
MD2 implementation in Erlang, as explained in http://www.umich.edu/~x509/ssleay/rfc1319.html
and corrected by http://www.rfc-editor.org/errata/rfc1319.

This is not optimized in any way, but was written just for fun.

# Example
```
1> Ctx = erl_md2:ctx_init().
2> NewCtx = erl_md2:ctx_update(Ctx, <<"abcdefghijklmnopqrstuvwxyz">>).
3> erl_md2:ctx_final(NewCtx).
"4e8ddff3650292ab5a4108c3aa47940b"
```

## License
The source code is released under Apache 2 License.

Check [LICENSE](https://github.com/marcelog/erl_lzw/blob/master/LICENSE) file for more information.
