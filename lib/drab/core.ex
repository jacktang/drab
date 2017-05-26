defmodule Drab.Core do
  @moduledoc ~S"""
  Drab Module with the basic communication from Server to the Browser. Does not require any libraries like jQuery,
  works on pure Phoenix.

      defmodule DrabPoc.JquerylessCommander do
        use Drab.Commander, modules: [] 

        def clicked(socket, payload) do
          socket |> console("You've sent me this: #{payload |> inspect}")
        end
      end

  See `Drab.Commander` for more info on Drab Modules.

  ## Events

  Events are defined directly in the HTML by adding `drab-event` and `drab-handler` properties:

      <button drab-event='click' drab-handler='button_clicked'>clickme</button>

  Clicking such button launches `DrabExample.PageCommander.button_clicked/2` on the Phoenix server.

  There are few shortcuts for the most popular events: `click`, `keyup`, `keydown`, `change`. For this event 
  an attribute `drab-EVENT_NAME` must be set. The following like is an equivalent for the previous one:

      <button drab-click='button_clicked'>clickme</button>

  Normally Drab operates on the user interface of the browser which generared the event, but it is possible to broadcast
  the change to all the browsers which are currently viewing the same page. See the bang functions in `Drab.Query` module.

  ## Event handler functions

  The event handler function receives two parameters:
  * `socket`     - the websocket used to communicate back to the page by `Drab.Query` functions
  * `dom_sender` - a map contains information of the object which sent the event; keys are binary strings

  The `dom_sender` map:

      %{
        "id"      => "sender object ID attribute",
        "name"    => "sender object 'name' attribute",
        "class"   => "sender object 'class' attribute",
        "text"    => "sender node 'text'",
        "html"    => "sender node 'html', result of running .html() on the node",
        "val"     => "sender object value",
        "data"    => "a map with sender object 'data-xxxx' attributes, where 'xxxx' are the keys",
        "event"   => "a map with choosen properties of `event` object"
        "drab_id" => "internal"
      }

  Example:

      def button_clicked(socket, dom_sender) do
        # using Drab.Query
        socket |> update(:text, set: "clicked", on: this(dom_sender))
      end

  ## Running Elixir code from the Browser

  There is the Javascript method `Drab.run_handler()` in global `Drab` object, which allows you to run the Elixir
  function defined in the Commander. 

      Drab.run_handler(event_name, function_name, argument)

  Arguments:
  * event_name(string) - name of the even which runs the function
  * function_name(string) - function name in corresponding Commander module
  * argument(anything) - any argument you want to pass to the Commander function

  Returns:
  * no return, does not wait for any answer

  Example:

      <button onclick="Drab.run_handler('click', 'clicked', {click: 'clickety-click'});">
        Clickme
      </button>

  The code above runs function named `clicked` in the corresponding Commander, with 
  the argument `%{"click" => "clickety-click}"`

  ## Store

  Analogically to Plug, Drab can store the values in its own session. To avoid confusion with the Plug Session session, 
  it is called a Store. You can use functions: `put_store/3` and `get_store/2` to read and write the values 
  in the Store. It works exactly the same way as a "normal", Phoenix session.

  * By default, Drab Store is kept in browser Local Storage. This means it is gone when you close the browser 
    or the tab. You may set up where to keep the data with drab_store_storage config entry.
  * Drab Store is not the Plug Session! This is a different entity. Anyway, you have an access 
    to the Plug Session (details below).
  * Drab Store is stored on the client side and it is signed, but - as the Plug Session cookie - not ciphered.

  ## Session

  Although Drab Store is a different entity than Plug Session (used in Controllers), there is a way 
  to access the Session. First, you need to whitelist the keys you wan to access in `access_session/1` macro 
  in the Commander (you may give it a list of atoms or a single atom). Whitelisting is due to security: 
  it is kept in Token, on the client side, and it is signed but not encrypted. 

      defmodule DrabPoc.PageCommander do
        use Drab.Commander

        onload :page_loaded, 
        access_session :drab_test

        def page_loaded(socket) do
          socket 
          |> update(:val, set: get_session(socket, :drab_test), on: "#show_session_test")
        end
      end

  There is not way to update session from Drab. Session is read-only.
  """
  require Logger

  # @behaviour Drab
  use DrabModule  
  # def prerequisites(), do: []
  def js_templates(), do: ["drab.core.js"]

  @doc """
  Synchronously executes the given javascript on the client side. 

  Returns tuple `{status, return_value}`, where status could be `:ok` or `:error`, and return value 
  contains the output computed by the Javascript or the error message.

  ### Options

  * `timeout` in milliseconds

  ### Examples

      iex> socket |> exec_js("2 + 2")                   
      {:ok, 4}

      iex> socket |> exec_js("not_existing_function()")
      {:error, "not_existing_function is not defined"}

      iex> socket |> exec_js("for(i=0; i<1000000000; i++) {}")
      {:error, "timed out after 5000 ms."}

      iex> socket |> exec_js("alert('hello from IEx!')", timeout: 500)               
      {:error, "timed out after 500 ms."}

  """
  def exec_js(socket, js, options \\ []) do
    Drab.push_and_wait_for_response(socket, self(), "execjs", [js: js], options)
  end

  @doc """
  Exception raising version of `exec_js/2`

  ### Examples

        iex> socket |> exec_js!("2 + 2")
        4

        iex> socket |> exec_js!("nonexistent")
        ** (Drab.JSExecutionError) nonexistent is not defined
            (drab) lib/drab/core.ex:100: Drab.Core.exec_js!/2

        iex> socket |> exec_js!("for(i=0; i<1000000000; i++) {}")                       
        ** (Drab.JSExecutionError) timed out after 5000 ms.
            (drab) lib/drab/core.ex:100: Drab.Core.exec_js!/2

        iex> socket |> exec_js!("for(i=0; i<10000000; i++) {}", timeout: 1000)         
        ** (Drab.JSExecutionError) timed out after 1000 ms.
            lib/drab/core.ex:114: Drab.Core.exec_js!/3

  """
  def exec_js!(socket, js, options \\ []) do
    case exec_js(socket, js, options) do
      {:ok, result} -> result
      {:error, message} -> raise Drab.JSExecutionError, message: message
    end
  end

  @doc false
  def execjs(socket, js) do
    Deppie.once("Drab.Core.execjs/2 is depreciated. Please use Drab.Core.exec_js/3 instead")
    {_, result} = exec_js(socket, js)
    result
  end

  @doc """
  Asynchronously broadcasts given javascript to all browsers, by default to all browsers connected to the same url.
  See `Drab.Commander.broadcasting/1` to find out how to change the default behaviour.

      iex> Drab.Core.broadcast_js(socket, "alert('Broadcasted to all!')")
      {:ok, :broadcasted}

  Always returns tuple `{:ok, :broadcasted}`
  """
  def broadcast_js(socket, js, _options \\ []) do
    Drab.broadcast(socket, self(), "broadcastjs", js: js)
    {:ok, :broadcasted}
  end

  @doc """
  Bang version of `Drab.Core.broadcast_js/3`

  Returns `socket`
  """
  def broadcast_js!(socket, js, _options \\ []) do
    Drab.broadcast(socket, self(), "broadcastjs", js: js)
    socket
  end

  @doc false
  def broadcastjs(socket, js) do
    Deppie.once("Drab.Core.broadcastjs/2 is depreciated. Please use Drab.Core.broadcast_js/3 instead")
    _ = broadcast_js(socket, js)
    socket
  end

  @doc """
  Moved to `Drab.Browser.console/2`
  """
  def console(socket, log) do
    Deppie.once """
    Drab.Core.console/2 is depreciated. Use Drab.Browser.console/2 instead.
    """
    Drab.Browser.console(socket, log)
  end

  @doc """
  Moved to `Drab.Browser.console!/2`
  """
  def console!(socket, log) do
    Deppie.once """
    Drab.Core.console!/2 is depreciated. Use Drab.Browser.console!/2 instead.
    """
    Drab.Browser.console!(socket, log)
  end

  @doc false
  def encode_js(value), do: Poison.encode!(value)

  @doc false
  def decode_js(value) do
    case Poison.decode(value) do
      {:ok, v} -> v
      _ -> value
    end
  end

  @doc """
  Returns the value of the Drab store represented by the given key.

      uid = get_store(socket, :user_id)
  """
  def get_store(socket, key) do
    store = Drab.get_store(socket.assigns.__drab_pid)
    store[key]
    # store(socket)[key]
  end

  @doc """
  Returns the value of the Drab store represented by the given key or `default` when key not found

      counter = get_store(socket, :counter, 0)
  """
  def get_store(socket, key, default) do
    get_store(socket, key) || default
  end

  @doc """
  Saves the key => value in the Store. Returns unchanged socket. 

      put_store(socket, :counter, 1)
  """
  def put_store(socket, key, value) do
    store = store(socket) |> Map.merge(%{key => value})
    {:ok, _} = exec_js(socket, "Drab.set_drab_store_token(\"#{tokenize_store(socket, store)}\")")

    # store the store in Drab server, to have it on terminate
    save_store(socket, store)

    socket
  end

  @doc false
  def save_store(socket, store) do
    Drab.update_store(socket.assigns.__drab_pid, store)
  end

  @doc """
  Returns the value of the Plug Session represented by the given key.

      counter = get_session(socket, :userid)

  You must explicit which session keys you want to access in `:access_session` option in `use Drab.Commander`.
  """
  def get_session(socket, key) do
    Drab.get_session(socket.assigns.__drab_pid)[key]
    # session(socket)[key]
  end

  @doc """
  Returns the value of the Plug Session represented by the given key or `default` when key not found

      counter = get_session(socket, :userid, 0)

  You must explicit which session keys you want to access in `:access_session` option in `use Drab.Commander`.
  """
  def get_session(socket, key, default) do
    get_session(socket, key) || default
  end

  @doc false
  def save_session(socket, session) do
    Drab.update_session(socket.assigns.__drab_pid, session)
  end

  @doc false
  def store(socket) do
    {:ok, store_token} = exec_js(socket, "Drab.get_drab_store_token()")
    detokenize_store(socket, store_token)
  end

  @doc false
  def session(socket) do
    {:ok, session_token} = exec_js(socket, "Drab.get_drab_session_token()")
    detokenize_store(socket, session_token)
  end

  @doc false
  def tokenize_store(socket, store) do
    Drab.tokenize(socket, store, "drab_store_token")
  end
 
  defp detokenize_store(_socket, drab_store_token) when drab_store_token == nil, do: %{} # empty store

  defp detokenize_store(socket, drab_store_token) do
    # we just ignore wrong token and defauklt the store to %{}
    # this is because it is read on connect, and raising here would cause infinite reconnects
    case Phoenix.Token.verify(socket, "drab_store_token", drab_store_token) do
      {:ok, drab_store} -> 
        drab_store
      {:error, _reason} -> 
        %{}
    end
  end
end
