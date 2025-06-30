package com.evervault.samplepayapp
import androidx.activity.result.ActivityResultLauncher
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.evervault.evpay.EvervaultPaymentButton
import com.evervault.evpay.EvervaultPayViewModel
import com.evervault.evpay.PaymentUiState
import com.evervault.evpay.Transaction
import com.google.android.gms.tasks.Task
import com.google.android.gms.wallet.PaymentData

@Composable
fun ProductScreen(
    title: String,
    description: String,
    price: String,
    image: Int,
    transaction: Transaction,
    model: EvervaultPayViewModel,
    payUiState: PaymentUiState = PaymentUiState.NotStarted,
    displayPaymentModalLauncher: ActivityResultLauncher<Task<PaymentData>>
) {
    val padding = 20.dp
    val black = Color(0xff000000.toInt())
    val grey = Color(0xffeeeeee.toInt())

    if (payUiState is PaymentUiState.PaymentCompleted) {
        Column(
            modifier = Modifier
                .testTag("successScreen")
                .background(grey)
                .padding(padding)
                .fillMaxWidth()
                .fillMaxHeight(),
            verticalArrangement = Arrangement.Center,
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Image(
                contentDescription = null,
                painter = painterResource(R.drawable.check_circle),
                modifier = Modifier
                    .width(200.dp)
                    .height(200.dp)
            )
            Spacer(modifier = Modifier.height(10.dp))
            Text(
                text = "${payUiState.response.billingAddress?.name} completed a payment.\nWe are preparing your order for shipping to ${payUiState.response.billingAddress?.address1} ${payUiState.response.billingAddress?.administrativeArea} ${payUiState.response.billingAddress?.countryCode}.",
                fontSize = 17.sp,
                color = Color.DarkGray,
                textAlign = TextAlign.Center
            )
            Spacer(modifier = Modifier.height(10.dp))
            Text(
                text = "PAN: ${payUiState.response.token.number}",
                fontSize = 17.sp,
                color = Color.DarkGray,
                textAlign = TextAlign.Center
            )
            Text(
                text = "Cryptogram: ${payUiState.response.cryptogram}",
                fontSize = 17.sp,
                color = Color.DarkGray,
                textAlign = TextAlign.Center
            )
        }

    } else {
        Column(
            modifier = Modifier
                .background(grey)
                .padding(padding)
                .fillMaxHeight(),
            verticalArrangement = Arrangement.spacedBy(space = padding / 2),
        ) {
            Image(
                contentDescription = null,
                painter = painterResource(image),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(350.dp)
            )
            Text(
                text = title,
                color = black,
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold
            )
            Text(text = price, color = black)
            Spacer(Modifier)
            Text(
                text = "Description",
                color = black,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = description,
                color = black
            )
            if (payUiState !is PaymentUiState.NotStarted) {
                EvervaultPaymentButton(
                    modifier = Modifier
                        .testTag("payButton")
                        .fillMaxWidth(),
                    transaction,
                    model,
                    displayPaymentModalLauncher
                )
            }
        }
    }
}