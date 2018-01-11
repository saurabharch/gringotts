defmodule Gringotts.Gateways.GlobalCollect do

  @base_url "https://api-sandbox.globalcollect.com/v1/1226/"
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
    number: "4567350000427977",
    month: 12,
    year: 18,
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

  @invoice %{
    invoiceNumber: "000000123",
    invoiceDate: "20140306191500"
  }

  @name %{
    title: "Miss",
    firstName: "Road",
    surname: "Runner"
  }

  @options [ email: "john@trexle.com", description: "Store Purchase 1437598192", currency: "USD", merchantCustomerId: "234", customer_name: "Jyoti", doB: "19490917", company: "asma", email: "jyotigautam108@gmail.com", phone: "7798578174", order_id: "2323", invoice: @invoice, billingAddress: @billingAddress, shippingAddress: @shippingAddress, name: @name, skipAuthentication: "true" ]

  def auth() do
    authorize(5, @payment, @options)
  end

  def capt() do
    capture("000000122600000000380000100001", 2500, @options)
  end

  def pur() do
    purchase(5, @payment, @options)
  end

  def ref() do
    refund(5, "000000122600000000380000100001", @options)
  end

  def voi() do
    void("000000122600000000380000100001", @options)
  end

  @spec authorize(float, CreditCard.t, list) :: map
  def authorize(amount, payment, opts) do
    params = create_params_for_auth_or_purchase(amount, payment, opts)
    commit(:post, "payments", params, opts)
  end

  @spec capture(String.t, float, list) :: map
  def capture(id, amount, opts) do
    params = create_params_for_capture(amount, opts)
    commit(:post, "payments/#{id}/approve", params, opts)
  end

  @spec purchase(float, CreditCard.t, list) :: map
  def purchase(amount, payment, opts) do
   {:ok,response} = authorize(amount, payment, opts)
   payment_Id = response.raw["payment"]["id"]
   capture(payment_Id, amount, opts)
  end

  @spec refund(float, String.t, list) :: map
  def refund(amount, id, opts) do
    params = create_params_for_refund(amount, opts)
    commit(:post, "payments/#{id}/refund", params, opts)
  end

  @spec void(String.t, list) :: map
  def void(id, opts) do
    params = nil
    commit(:post, "payments/#{id}/cancel", params, opts)
  end

  defp create_params_for_refund(amount, opts) do
    %{
      amountOfMoney: add_money(amount, opts),
      customer: add_customer(opts)
    }
  end

  defp create_params_for_auth_or_purchase(amount, payment, opts) do
    %{
      order: add_order(amount, opts),
      cardPaymentMethodSpecificInput: add_payment(payment, @brand_map, opts)
    }
  end

   defp create_params_for_capture(amount, opts) do
    %{
      order: add_order(amount, opts)
    }
  end

  defp add_order(money, options) do
    %{
      amountOfMoney: add_money(money, options),
      customer: add_customer(options),
      references: add_references(options)
    }
  end

  defp add_money(amount, options) do
    %{
      amount: amount,
      currencyCode: options[:currency]
    }
  end

  defp add_customer(options) do
    %{
      merchantCustomerId: options[:merchantCustomerId],
      personalInformation: personal_info(options),
      dateOfBirth: options[:doB],
      companyInformation: company_info(options),
      billingAddress: options[:billingAddress],
      shippingAddress: options[:shippingAddress],
      contactDetails: contact(options)
    }
  end

  defp add_references(options) do
    %{
      descriptor: options[:description],
      invoiceData: options[:invoice]
    }
  end

  defp personal_info(options) do
    %{
      name: options[:name]
    }
  end

  defp company_info(options) do
    %{
      name: options[:company]
    }
  end

  defp contact(options) do
    %{
      emailAddress: options[:email],
      phoneNumber: options[:phone]
    }
  end

  def add_card(%CreditCard{} = payment) do
    %{
      cvv: payment.verification_code,
      cardNumber: payment.number,
      expiryDate:  "#{payment.month}"<>"#{payment.year}",
      cardholderName: CreditCard.full_name(payment)
    }
  end

  defp add_payment(payment, brand_map, opts) do
    brand = payment.brand
    %{
      paymentProductId:  Map.fetch!(brand_map, String.to_atom(brand)),
      skipAuthentication: opts[:skipAuthentication],
      card: add_card(payment)
    }
  end

  defp auth_digest(path, secret_api_key, time) do
    data = "POST\napplication/json\n#{time}\n/v1/1226/#{path}\n"
    :crypto.hmac(:sha256, secret_api_key, data)
  end

  defp commit(method, path, params, opts) do
    time = date
    sha_signature = auth_digest(path, @secret_api_key, time) |> Base.encode64
    auth_token = "GCS v1HMAC:#{@api_key_id}:#{sha_signature}"
    headers = [{"Content-Type", "application/json"}, {"Authorization", auth_token}, {"Date", time}]
    data = Poison.encode!(params)
    url = "#{@base_url}#{path}"
    response = HTTPoison.request(method, url, data, headers)
    response |> respond
  end

  defp date() do
    use Timex
    datetime = Timex.now |> Timex.local
    strftime_str = Timex.format!(datetime, "%a, %d %b %Y %H:%M:%S ", :strftime)
    time_zone = Timex.timezone(:local, datetime)
    time = strftime_str <>"#{time_zone.abbreviation}"
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
