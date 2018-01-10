defmodule Gringotts.Gateways.GlobalCollect do

  @base_url "https://api-sandbox.globalcollect.com/v1/1226"
  @api_key_id "e5743abfc360ed12"
  @secret_api_key "Qtg9v4Q0G13sLRNcClWhHnvN1kVYWDcy4w9rG8T86XU="


  use Gringotts.Gateways.Base
  import Poison, only: [decode: 1]
  alias Gringotts.{Response, CreditCard, Address}
  @brand_map  %{
    "visa": "1",
    "american_express": "2",
    "master": "3",
    "discover": "128",
    "jcb": "125",
    "diners_club": "132"
  }

  @shippingAddress %{
    street: "Desertroad",
    houseNumber: "1",
    additionalInfo: "Suite II",
    zip: "84536",
    city: "Monument Valley",
    state: "Utah",
    countryCode: "US"
  }

  @payment %CreditCard{
    number: "5200828282828210",
    month: 12,
    year: 2018,
    first_name: "John",
    last_name: "Doe",
    verification_code: "123",
    brand: "visa"
  }

  @billingAddress %{
    street: "Desertroad",
    houseNumber: "13",
    additionalInfo: "b",
    zip: "84536",
    city: "Monument Valley",
    state: "Utah",
    countryCode: "US"

  }

  options = [ email: "john@trexle.com", description: "Store Purchase 1437598192", currency: "USD", merchantCustomerId: "234", customer_name: "Jyoti", doB: "19490917", company: "asma", email: "jyotigautam108@gmail.com", phone: "7798578174", order_id: "2323", invoice: "3433533", billingAddress: @billingAddress, shippingAddress: @shippingAddress ]

  @spec authorize(float, CreditCard.t, list) :: map
  def authorize(amount = 5, payment = @payment, opts) do
    params = create_params_for_auth_or_purchase(amount, payment, opts, false)
    commit(:post, "payments", params, @opts)
  end

  defp create_params_for_auth_or_purchase(amount, payment, opts, capture \\ true) do
    [
    ]
      ++ add_order(amount, opts)
      ++ add_payment(payment, @brand_map)
  end

  defp add_order(money, options) do
    [
      "order[amountOfMoney][amount]": money,
      "order[amountOfMoney][currencyCode]": options[:currency],
      "order[customer][merchantCustomerId]": options[:merchantCustomerId],
      "order[customer][personalInformation][name]": options[:customer_name],
      "order[customer][dateOfBirth]": options[:doB],
      "order[customer][companyInformation][name]": options[:company],
      "order[customer][billingAddress]": options[:billingAddress],
      "order[customer][shippingAddress]": options[:shippingAddress],
      "order[customer][contactDetails][emailAddress]": options[:email],
      "order[customer][contactDetails][phoneNumber]": options[:phone],
      "order[references][merchantReference]": options[:order_id],
      "order[references][descriptor]": options[:description], # Max 256 chars
      "order[references][invoiceData][invoiceNumber]": options[:invoice]
    ]
  end

  defp add_payment(%CreditCard{} = payment, brand_map) do
    brand = payment.brand
    require IEx
    IEx.pry
    [
      "cardPaymentMethodSpecificInput[paymentProductId]": brand_map.brand,
      "cardPaymentMethodSpecificInput[skipAuthentication]": "true", # refers to 3DSecure
      "cardPaymentMethodSpecificInput[card][cvv]": payment.verification_code,
      "cardPaymentMethodSpecificInput[card][cardNumber]": payment.number,
      "cardPaymentMethodSpecificInput[card][expiryDate]": payment.month<>payment.year,
      "cardPaymentMethodSpecificInput[card][cardholderName]": CreditCard.full_name(payment)
    ]
  end

  defp auth_digest(path, secret_api_key, time) do
    data = "POST\napplication/json\n#{time}\n/v1/1226/#{path}\n"
    :crypto.hmac(:sha256, secret_api_key, data)
  end

  defp commit(method, path, params, opts) do
    time = date
    sha_signature = auth_digest(path, @secret_api_key, time)
    auth_token = "GCS v1HMAC:#{@api_key_id}:#{Base.encode64(sha_signature)}"
    headers = [{"Content-Type", "application/json"}, {"Authorization", auth_token}, {"Date", time}]
    data = params_to_string(params)
    #options = [hackney: [:insecure, basic_auth: {opts[:config][:api_key], "password"}]]
    url = "#{@base_url}#{path}"
    response = HTTPoison.request(method, url, data, headers)
    response |> respond
  end

  defp date() do
    use Timex
    datetime = Timex.now
    strftime_str = Timex.format!(datetime, "%a, %d %b %Y %H:%M:%S ", :strftime)
    time = strftime_str <>"IST"
  end

  @spec respond(term) ::
  {:ok, Response} |
  {:error, Response}
  defp respond(response)

  defp respond({:ok, %{status_code: code, body: body}}) when code in [200, 201] do
    case decode(body) do
      {:ok, results} -> {:ok, Response.success(raw: results, status_code: code)}
    end
  end

  defp respond({:ok, %{status_code: status_code, body: body}}) do
    {:error, Response.error(status_code: status_code, raw: body)}
  end

  defp respond({:error, %HTTPoison.Error{} = error}) do
    {:error, Response.error(code: error.id, reason: :network_fail?, description: "HTTPoison says '#{error.reason}'")}
  end

end
