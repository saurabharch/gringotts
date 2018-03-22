defmodule Gringotts.Gateways.SecurionPay do
  @moduledoc """
  [SecurionPay][home] gateway implementation.

  For reference see [SecurionPay's API (v1) documentation][docs].

  The following set of functions for SecurionPay have been implemented:

  | Action                                       | Method        |
  | ------                                       | ------        |
  | Authorize a Credit Card                      | `authorize/3` |
  | Captures a previously authorized amount      | `capture/3`   |
  |	Create customer's profile					 | `store/2`     |

  [home]: https://securionpay.com/
  [docs]: https://securionpay.com/docs

  ## The `opts` argument

  Most `Gringotts` API calls accept an optional `keyword` list `opts` to supply
  [optional arguments][extra-arg-docs] for transactions with the SecurionPay
  gateway. The following keys are supported:

  | Key                      | Remark                                                                                        |
  | ----                     | ---                                                                                           |
  | `customerId`             | Unique identifier of the customer                                                             |

  ## Registering your SecurionPay account at `Gringotts`

  After [making an account on SecurionPay][SP], find your `Secret key` at [Account Settings][api-key] 

  Your Application config **must include the `:secret_key`  field**.
  It would look something like this:

      config :gringotts, Gringotts.Gateways.SecurionPay,
        secret_key: "your_secret_key"

  [SP]: https://securionpay.com/
  [api-key]: https://securionpay.com/account-settings#api-keys


  ## Note

  * SecurionPay always processes the transactions in the minor units of the currency 
  For example `cent` instead of `dollar`

  ## Supported countries

  SecurionPay supports the countries listed [here][country-list]

  [country-list]: https://securionpay.com/supported-countries-businesses/
  """

  @base_url "https://api.securionpay.com/"
  # The Base module has the (abstract) public API, and some utility
  # implementations.

  use Gringotts.Gateways.Base

  # The Adapter module provides the `validate_config/1`
  # Add the keys that must be present in the Application config in the
  # `required_config` list
  use Gringotts.Adapter, required_config: [:secret_key]

  import Poison, only: [decode: 1]

  alias Gringotts.{CreditCard, Response, Address}

  @doc """
  Authorizes a credit card transaction.

  The authorization validates the `card` details with the banking network,
  places a hold on the transaction `amount` in the customer’s issuing bank and
  also triggers risk management. Funds are not transferred.

  The second argument can be a CreditCard or a cardId. The customerId of the cutomer who owns the card must be
  given in optional field. 

  To transfer the funds to merchant's account follow this up with a `capture/3`.

  SecurionPay returns a `chargeId` which uniquely identifies a transaction (available in the `Response.id` field) 
  which should be stored by the caller for using in:

  * `capture/3` an authorized transaction.
  * `void/2` a transaction.

  ## Example
  ### With a `CreditCard` struct
      iex> amount = Money.new(20, :USD)
      iex> opts = [config: [secret_key: "c2tfdGVzdF9GZjJKcHE1OXNTV1Q3cW1JOWF0aWk1elI6"]]
      iex> card = %CreditCard{
           first_name: "Harry",
           last_name: "Potter",
           number: "4200000000000000",
           year: 2027,
           month: 12,
           verification_code: "123",
           brand: "VISA"
          }
      iex> result = Gringotts.Gateways.SecurionPay.authorize(amount, card, opts)

  ## Example
  ### With a `card_token` and `customer_token`
      iex> amount = Money.new(20, :USD}
      iex> opts = [config: [:secret_key: "c2tfdGVzdF9GZjJKcHE1OXNTV1Q3cW1JOWF0aWk1elI6"], customer_id: "cust_zpYEBK396q3rvIBZYc3PIDwT"]
      iex> card = "card_LqTT5tC10BQzDbwWJhFWXDoP"
      iex> result = Gringotts.Gateways.SecurionPay.authorize(amount, card, opts)

  """
  @spec authorize(Money.t(), CreditCard.t() | String.t(), keyword) :: {:ok | :error, Response}
  def authorize(amount, %CreditCard{} = card, opts) do
    header = [{"Authorization", "Basic " <> opts[:config][:secret_key]}]
    token_id = create_token(card, header)
    {currency, value, _, _} = Money.to_integer_exp(amount)

    token_id
    |> create_params(currency, value, false)
    |> commit(:post, "charges", header)
    |> respond
  end

  def authorize(amount, card_id, opts) when is_binary(card_id) do
    header = [{"Authorization", "Basic " <> opts[:config][:secret_key]}]
    {currency, value, _, _} = Money.to_integer_exp(amount)
    params = create_params(card_id, opts[:customer_id], currency, value, false)

    params
    |> commit(:post, "charges", header)
    |> respond
  end

  @doc """
  Captures a pre-authorized transcation from the customer.

  The amount present in the pre-authorization referenced by `payment_id` is transferred to the 
  merchant account by SecurionPay.


  Successful request returns a charge object that was captured.

  ## Note
  > SecurionPay does not support partial captures. So there is no need of amount in capture.

  ## Example
      iex> opts = [config: [secret_key: "c2tfdGVzdF82cGZBYTI3aDhvOUUxanRJZWhaQkE3dkE6"]]
      iex> amount = 100
      iex> payment_id = "char_WCglhaf1Gn9slpXWYBkZqbGK" 
      iex> result = Gringotts.Gateways.SecurionPay.capture(payment_id, amount, opts)     

  """
  @spec capture(String.t(), Money.t(), keyword) :: {:ok | :error, Response}
  def capture(payment_id, _amount, opts) do
    header = [{"Authorization", "Basic " <> opts[:config][:secret_key]}]

    commit([], :post, "charges/#{payment_id}/capture", header)
    |> respond
  end

  @doc """
  Stores the customer's card details for later use.

  SecurionPay can store the payment-source details, for example card  details
  which can be used to effectively process _One-Click_ payments, and returns a 
  card id which can be used for `purchase/3`, `authorize/3` and `unstore/2`.

  The card id is available in the `Response.id` field.

  It is **mandatory** to pass either `:email` or `:customer_id` in the opts field.

  Here `store/2` is implemented in two ways:
  * `:customer_id` is available in the opts field
  * `:email` is available in the opts field(`:customer_id` not available)

  ## Example
  ### With the `:customer_id` available in the opts field
      iex> opts = [config: [secret_key: "c2tfdGVzdF9GZjJKcHE1OXNTV1Q3cW1JOWF0aWk1elI6"], customer_id: "cust_zpYEBK396q3rvIBZYc3PIDwT"]
      iex> card = %CreditCard{
           first_name: "Harry",
           last_name: "Potter",
           number: "4200000000000000",
           year: 2027,
           month: 12,
           verification_code: "123",
           brand: "VISA"
          }	
      iex> result = Gringotts.Gateways.SecurionPay.store(card, opts)
  ## Example
  ### With `:email` in the opts field
      iex> opts = [config: [secret_key: "c2tfdGVzdF9GZjJKcHE1OXNTV1Q3cW1JOWF0aWk1elI6"], email: "customer@example.com"]
      iex> card = %CreditCard{
           first_name: "Harry",
           last_name: "Potter",
           number: "4200000000000000",
           year: 2027,
           month: 12,
           verification_code: "123",
           brand: "VISA"
          }	
      iex> result = Gringotts.Gateways.SecurionPay.store(card, opts)
           
  """
  @spec store(CreditCard.t(), Keyword.t()) :: {:ok | :error, Response.t()}
  def store(card, opts) do
    header = [{"Authorization", "Basic " <> opts[:config][:secret_key]}]

    if Keyword.has_key?(opts, :customer_id) do
      card |> create_card(opts, header)
    else
      card |> create_customer(opts, header)
    end
  end

  ###############################################################################
  #                                PRIVATE METHODS                              #
  ###############################################################################

  # Creates the parameters for authorise function when 
  # card_id and customerId is provided.

  # @spec create_card()
  defp create_card(card, opts, header) do
    [
      {"number", card.number},
      {"expMonth", card.month},
      {"expYear", card.year},
      {"cvc", card.verification_code}
    ]
    |> commit(:post, "customers/#{opts[:customer_id]}/cards", header)
  end

  # @spec create_customer()
  defp create_customer(card, opts, header) do
    customer_id =
      [{"email", opts[:email]}]
      |> commit(:post, "customers", header)
      |> make_map
      |> Map.fetch!("id")

    create_card(card, opts ++ [customer_id: customer_id], header)
  end

  @spec create_params(String.t(), String.t(), String.t(), Integer.t(), boolean) :: {[]}
  defp create_params(card_id, customer_id, currency, value, captured) do
    [
      {"amount", value},
      {"currency", to_string(currency)},
      {"card", card_id},
      {"captured", "#{captured}"},
      {"customerId", customer_id}
    ]
  end

  # Creates the parameters for authorise when token is provided.
  @spec create_params(String.t(), String.t(), Integer.t(), boolean) :: {[]}
  defp create_params(token, currency, value, captured) do
    [
      {"amount", value},
      {"currency", to_string(currency)},
      {"card", token},
      {"captured", "#{captured}"}
    ]
  end

  # Makes the request to SecurionPay's network.
  # For consistency with other gateway implementations, make your (final)
  # network request in here, and parse it using another private method called
  # `respond`.
  defp commit(params, method, path, header) do
    HTTPoison.request(method, "#{@base_url}#{path}", {:form, params}, header)
  end

  # Parses SecurionPay's response and returns a `Gringotts.Response` struct
  # in a `:ok`, `:error` tuple.
  @spec respond(term) :: {:ok | :error, Response}

  defp respond({:ok, %{status_code: 200, body: body}}) do
    parsed_body = Poison.decode!(body)

    {:ok,
     %{
       success: true,
       id: Map.get(parsed_body, "id"),
       token: Map.get(parsed_body["card"], "id"),
       status_code: 200,
       raw: body,
       fraud_review: Map.get(parsed_body, "fraudDetails")
     }}
  end

  defp respond({:ok, %{body: body, status_code: code}}) do
    {:error, %Response{raw: body, status_code: code}}
  end

  defp respond({:error, %HTTPoison.Error{} = error}) do
    {
      :error,
      %Response{
        reason: "network related failure",
        message: "HTTPoison says '#{error.reason}' [ID: #{error.id || "nil"}]"
      }
    }
  end

  defp create_token(card, header) do
    [
      {"number", card.number},
      {"expYear", card.year},
      {"cvc", card.verification_code},
      {"expMonth", card.month},
      {"cardholderName", CreditCard.full_name(card)}
    ]
    |> commit(:post, "tokens", header)
    |> make_map
    |> Map.fetch!("id")
  end

  defp make_map(response) do
    case response do
      {:ok, %HTTPoison.Response{body: body}} -> body |> Poison.decode!()
    end
  end
end
