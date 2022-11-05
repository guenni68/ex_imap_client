defmodule ExImapClient.ResponseParserTestSupport do
  @moduledoc false
  alias ExImapClient.ResponseParser

  use ParserBuilder.TestSupport,
    tests: "priv/test/imap_grammar_tests.xml",
    parser_module: ResponseParser
end
