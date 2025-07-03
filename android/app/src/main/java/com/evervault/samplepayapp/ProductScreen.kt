package com.evervault.samplepayapp
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.evervault.googlepay.ButtonTheme
import com.evervault.googlepay.ButtonType
import com.evervault.googlepay.EvervaultPaymentButton
import com.evervault.googlepay.EvervaultPayViewModel
import com.evervault.googlepay.Transaction

@Composable
fun ProductScreen(
    transaction: Transaction,
    model: EvervaultPayViewModel,
    theme: ButtonTheme,
    type: ButtonType,
) {
    val padding = 20.dp
    val black = Color(0xff000000.toInt())
    val grey = Color(0xffeeeeee.toInt())

    Column(
        modifier = Modifier
            .background(grey)
            .padding(padding)
            .fillMaxHeight(),
        verticalArrangement = Arrangement.spacedBy(space = padding / 2),
    ) {
        Image(
            contentDescription = null,
            painter = painterResource(R.drawable.ts_10_11019a),
            modifier = Modifier
                .fillMaxWidth()
                .height(350.dp)
        )
        Text(
            text = "Men's Tech Shell Full-Zip",
            color = black,
            fontSize = 20.sp,
            fontWeight = FontWeight.Bold
        )
        Text(text = "$50.20", color = black)
        Spacer(Modifier)
        Text(
            text = "Description",
            color = black,
            fontWeight = FontWeight.Bold
        )
        Text(
            text = "A versatile full-zip that you can wear all day long and even...",
            color = black
        )
        EvervaultPaymentButton(
            modifier = Modifier
                .testTag("payButton")
                .fillMaxWidth(),
            transaction,
            model,
            theme,
            type,
        )
    }
}