class Provider::Frankfurter < Provider
  include ExchangeRateConcept

  Error = Class.new(Provider::Error)
  InvalidExchangeRateError = Class.new(Error)

  def healthy?
    with_provider_response do
      response = client.get("/v1/latest", from: "USD", to: "USD")
      JSON.parse(response.body).dig("rates", "USD").present?
    end
  end

  def fetch_exchange_rate(from:, to:, date:)
    with_provider_response do
      response = client.get("/v1/#{date}", from: from, to: to)
      rate = JSON.parse(response.body).dig("rates", to)

      raise InvalidExchangeRateError, "No rate returned for #{from}->#{to} on #{date}" unless rate

      Rate.new(date: date.to_date, from:, to:, rate:)
    end
  end

  def fetch_exchange_rates(from:, to:, start_date:, end_date:)
    with_provider_response do
      response = client.get("/v1/#{start_date}..#{end_date}", from: from, to: to)
      rates_by_date = JSON.parse(response.body).dig("rates") || {}

      rates_by_date.filter_map do |date, rates|
        rate = rates[to]
        Rate.new(date: date.to_date, from:, to:, rate:) if rate
      end
    end
  end

  private
    # Frankfurter (ECB reference rates) covers ~30 major currencies, not the full ISO list,
    # and has no weekend/holiday rates — ExchangeRate::Importer already gapfills those.
    def base_url
      ENV["FRANKFURTER_URL"] || "https://api.frankfurter.dev"
    end

    def client
      @client ||= Faraday.new(url: base_url) do |faraday|
        faraday.request(:retry, {
          max: 2,
          interval: 0.05,
          interval_randomness: 0.5,
          backoff_factor: 2
        })

        faraday.response :raise_error
      end
    end
end
