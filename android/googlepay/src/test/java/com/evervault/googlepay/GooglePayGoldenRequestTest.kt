package com.evervault.googlepay

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Test
import org.skyscreamer.jsonassert.JSONAssert
import org.skyscreamer.jsonassert.JSONCompareMode

/**
 * Fixture tests for the whole Google Pay payment request.
 *
 * These fixtures are shared with the web SDK's `packages/ui-components/test/fixtures/google-pay`.
 * Keep the two copies identical so a default that drifts on one platform fails here.
 */
class GooglePayGoldenRequestTest {
    private val merchantName = "Test Merchant"
    private val config = Config(appId = "app_123", merchantId = "merchant_123")
    private val transaction = Transaction(
        country = "IE",
        currency = "EUR",
        total = Amount.ofMinorUnits(5499),
        lineItems = arrayOf(LineItem("Shell Jacket", Amount.ofMinorUnits(5000)))
    )

    private fun fixture(name: String): String {
        val stream = requireNotNull(javaClass.classLoader?.getResourceAsStream("google-pay/$name.json"))
        return stream.bufferedReader().use { it.readText() }
    }

    /**
     * Projects the request onto the fields web and Android share.
     *
     * `displayItems[].status` is required by the Google Pay Android client and has no web
     * equivalent, so it is covered by its own test rather than by the shared fixtures.
     */
    private fun comparableRequest(config: Config, transaction: Transaction): JSONObject {
        val request = JSONObject(buildPaymentRequestJson(config, transaction, merchantName))
        val transactionInfo = request.getJSONObject("transactionInfo")
        val displayItems = transactionInfo.getJSONArray("displayItems")
        for (index in 0 until displayItems.length()) {
            displayItems.getJSONObject(index).remove("status")
        }

        return JSONObject()
            .put("apiVersion", request.getInt("apiVersion"))
            .put("apiVersionMinor", request.getInt("apiVersionMinor"))
            .put("emailRequired", request.getBoolean("emailRequired"))
            .put("allowedPaymentMethods", request.getJSONArray("allowedPaymentMethods"))
            .put("merchantInfo", JSONObject().put("merchantName", merchantName))
            .put("transactionInfo", transactionInfo)
    }

    private fun assertMatchesFixture(name: String, config: Config, transaction: Transaction) {
        JSONAssert.assertEquals(
            fixture(name),
            comparableRequest(config, transaction),
            JSONCompareMode.STRICT
        )
    }

    @Test
    fun `the default request matches the disabled-billing fixture`() {
        assertMatchesFixture("billing-disabled", config, transaction)
    }

    @Test
    fun `explicitly enabled billing matches the enabled-billing fixture`() {
        assertMatchesFixture(
            "billing-enabled",
            config.copy(billingAddress = BillingAddressConfig.Enabled()),
            transaction
        )
    }

    @Test
    fun `disabled billing matches the disabled-billing fixture`() {
        assertMatchesFixture(
            "billing-disabled",
            config.copy(billingAddress = BillingAddressConfig.Disabled),
            transaction
        )
    }

    @Test
    fun `a fully configured request matches the custom fixture`() {
        assertMatchesFixture(
            "custom",
            config.copy(
                emailRequired = true,
                supportedMethods = listOf(CardAuthMethod.PAN_ONLY),
                supportedNetworks = listOf(CardNetwork.INTERAC),
                billingAddress = BillingAddressConfig.Enabled(BillingAddressFormat.MIN, true)
            ),
            transaction.copy(priceLabel = "Subscription")
        )
    }

    @Test
    fun `display items carry the Android-only status field`() {
        val request = JSONObject(buildPaymentRequestJson(config, transaction, merchantName))
        val displayItems: JSONArray = request.getJSONObject("transactionInfo").getJSONArray("displayItems")

        assertEquals(1, displayItems.length())
        assertEquals("FINAL", displayItems.getJSONObject(0).getString("status"))
    }
}
