defmodule ExImapClient.ResponseParser do
  use ParserBuilder, file: "priv/imap_grammar.xml"

  alias ExImapClient.ResponseParser.Transformer

  def transform_ast(ast) do
    Transformer.transform_ast(ast)
  end
end
