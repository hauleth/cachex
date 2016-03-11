defmodule Cachex.Options do
  @moduledoc false
  # A container to ensure that all option parsing is done in a single location
  # to avoid accidentally getting mixed field names and values across the library.

  # add some aliases
  alias Cachex.Hook
  alias Cachex.Util

  defstruct cache: nil,             # the name of the cache
            ets_opts: nil,          # any options to give to ETS
            default_fallback: nil,  # the default fallback implementation
            default_ttl: nil,       # any default ttl values to use
            fallback_args: nil,     # arguments to pass to a cache loader
            pre_hooks: nil,         # any pre hooks to attach
            post_hooks: nil,        # any post hooks to attach
            nodes: nil,             # a list of nodes to connect to
            remote: nil,            # are we using a remote implementation
            transactional: nil,     # use a transactional implementation
            ttl_interval: nil       # the ttl check interval

  @doc """
  Parses a list of input options to the fields we care about, setting things like
  defaults and verifying types. The output of this function should be a set of
  options that we can use blindly in other areas of the library. As such, this
  function has the potential to become a little messy - but that's okay, since
  it saves us trying to duplicate this logic all over the codebase.
  """
  def parse(options \\ []) do
    cache = case options[:name] do
      val when val == nil or not is_atom(val) ->
        raise "Cache name must be a valid atom!"
      val -> val
    end

    ets_opts = Keyword.get(options, :ets_opts, [
      { :read_concurrency, true },
      { :write_concurrency, true }
    ])

    default_ttl = parse_number_option(options, :default_ttl)

    default_interval = case (!!default_ttl) do
      true  -> 1000
      false -> nil
    end

    ttl_interval = case options[:ttl_interval] do
      nil -> default_interval
      val when not is_number(val) or val < 0 -> nil
      val -> val
    end

    default_fallback = case options[:default_fallback] do
      fun when is_function(fun) -> fun
      _fn -> nil
    end

    fallback_args = case options[:fallback_args] do
      args when not is_list(args) -> {}
      args -> Util.list_to_tuple(args)
    end

    nodes = case options[:nodes] do
      nodes when not is_list(nodes) -> nil
      nodes -> nodes
    end

    hooks = case options[:hooks] do
      nil -> []
      mod -> Hook.initialize_hooks(mod)
    end

    stats_hook = case !!options[:record_stats] do
      true ->
        tmp_hook = %Hook{
          module: Cachex.Stats,
          type: :post,
          results: true,
          ref: Cachex.Util.stats_for_cache(cache)
        }
        Hook.initialize_hooks(tmp_hook)
      false ->
        []
    end

    pre_hooks = Hook.hooks_by_type(hooks, :pre)
    post_hooks = stats_hook ++ Hook.hooks_by_type(hooks, :post)

    %__MODULE__{
      "cache": cache,
      "ets_opts": ets_opts,
      "default_fallback": default_fallback,
      "default_ttl": default_ttl,
      "fallback_args": fallback_args,
      "nodes": nodes,
      "pre_hooks": pre_hooks,
      "post_hooks": post_hooks,
      "remote": (nodes != nil && nodes != [node()] || !!options[:remote]),
      "transactional": !!options[:transactional],
      "ttl_interval": ttl_interval
    }
  end

  # Retrieves a field from the options as a number. Numbers must be strictly
  # positive for our uses, so if the value is not a number (or is less than 0)
  # we move to a default value. If no default is provided, we just nil the value.
  defp parse_number_option(options, key, default \\ nil) do
    case options[key] do
      val when not is_number(val) or val < 1 -> default
      val -> val
    end
  end

end
