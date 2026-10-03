package com.alphabubble

import android.graphics.Bitmap
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalContext
import androidx.core.graphics.drawable.toBitmap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

val Ink = Color(0xFF0B0C0E)
val Paper = Color(0xFFE8E6E1)
val Mint = Color(0xFF5DCAA5)
val Amber = Color(0xFFEF9F27)
val Coral = Color(0xFFE5766B)

class UiCfg(
    val accent: Color = Paper,
    val cardAlpha: Float = 0.72f,
    val contrast: Float = 0.7f,
    val saver: Boolean = false,
)

val LocalUi = compositionLocalOf { UiCfg() }

val Mono = FontFamily.Monospace

@Composable
fun muted(): Color = Color.White.copy(alpha = 0.35f + 0.5f * LocalUi.current.contrast)

@Composable
fun txt(
    s: String,
    size: TextUnit = 13.sp,
    color: Color = Paper,
    weight: FontWeight = FontWeight.Normal,
    modifier: Modifier = Modifier,
    align: TextAlign = TextAlign.Start,
    spacing: TextUnit = 0.sp,
    maxLines: Int = Int.MAX_VALUE,
) {
    Text(
        text = s, modifier = modifier, color = color, fontSize = size, fontFamily = Mono,
        fontWeight = weight, textAlign = align, letterSpacing = spacing, maxLines = maxLines,
        overflow = TextOverflow.Ellipsis,
    )
}

@Composable
fun Label(s: String, modifier: Modifier = Modifier) {
    txt(s.uppercase(), 11.sp, muted(), modifier = modifier.padding(bottom = 6.dp), spacing = 1.6.sp)
}

@Composable
fun AlphaCard(
    modifier: Modifier = Modifier,
    isNew: Boolean = false,
    onClick: (() -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    val ui = LocalUi.current
    val shape = RoundedCornerShape(22.dp)
    var m = modifier
        .fillMaxWidth()
        .padding(bottom = 10.dp)
        .clip(shape)
        .background(Ink.copy(alpha = ui.cardAlpha))
        .border(BorderStroke(0.6.dp, if (isNew) Mint else Color.White.copy(alpha = 0.14f)), shape)
    if (onClick != null) m = m.clickable(onClick = onClick)
    Column(m.padding(14.dp)) { content() }
}

@Composable
fun KV(k: String, v: String, onClick: (() -> Unit)? = null) {
    var m = Modifier.fillMaxWidth().padding(vertical = 7.dp)
    if (onClick != null) m = m.clickable(onClick = onClick)
    Row(m, horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
        txt(k, color = muted(), modifier = Modifier.weight(1f))
        txt(v, align = TextAlign.End, modifier = Modifier.weight(1f))
    }
}

@Composable
fun Divider() {
    Box(Modifier.fillMaxWidth().height(0.5.dp).background(Color.White.copy(alpha = 0.1f)))
}

@Composable
fun Seg(options: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    val ui = LocalUi.current
    Row(
        modifier.fillMaxWidth().padding(vertical = 4.dp).clip(CircleShape).background(Color.Black.copy(alpha = 0.55f)).padding(4.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        options.forEachIndexed { i, o ->
            val on = i == selected
            Box(
                Modifier.weight(1f).clip(CircleShape)
                    .background(if (on) ui.accent else Color.Transparent)
                    .clickable { onSelect(i) }.padding(vertical = 10.dp),
                contentAlignment = Alignment.Center,
            ) {
                txt(o, 12.sp, if (on) Ink else muted(), spacing = 1.sp, maxLines = 1)
            }
        }
    }
}

@Composable
fun Pill(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    highlight: Boolean = false,
    solid: Boolean = false,
) {
    val ui = LocalUi.current
    val bg = if (solid) ui.accent else Color.Transparent
    val fg = if (solid) Ink else if (enabled) Paper else muted()
    Box(
        modifier.fillMaxWidth().padding(top = 8.dp).clip(CircleShape).background(bg)
            .border(BorderStroke(0.6.dp, if (highlight) Mint else Color.White.copy(alpha = 0.25f)), CircleShape)
            .clickable(enabled = enabled, onClick = onClick).padding(vertical = 12.dp),
        contentAlignment = Alignment.Center,
    ) { txt(text, 12.sp, fg, spacing = 1.6.sp, maxLines = 1) }
}

@Composable
fun SmallPill(text: String, onClick: (() -> Unit)? = null, highlight: Boolean = false) {
    var m = Modifier.clip(CircleShape).border(BorderStroke(0.6.dp, if (highlight) Mint else Color.White.copy(alpha = 0.3f)), CircleShape)
    if (onClick != null) m = m.clickable(onClick = onClick)
    Box(m.padding(horizontal = 10.dp, vertical = 4.dp)) { txt(text, 11.sp, if (highlight) Mint else Paper, maxLines = 1) }
}

@Composable
fun NewTag(modifier: Modifier = Modifier) {
    Box(modifier.clip(CircleShape).background(Mint).padding(horizontal = 8.dp, vertical = 1.dp)) {
        txt("NEW", 10.sp, Color(0xFF04342C), FontWeight.Medium, spacing = 0.8.sp)
    }
}

@Composable
fun Toggle(on: Boolean, onChange: (Boolean) -> Unit) {
    val ui = LocalUi.current
    Box(
        Modifier.width(44.dp).height(26.dp).clip(CircleShape)
            .background(if (on) ui.accent else Color(0xFF2A2D33))
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) { onChange(!on) }
            .padding(3.dp),
        contentAlignment = if (on) Alignment.CenterEnd else Alignment.CenterStart,
    ) {
        Box(Modifier.size(20.dp).clip(CircleShape).background(if (on) Ink else Color(0xFF8A8A8A)))
    }
}

@Composable
fun ToggleRow(title: String, sub: String? = null, on: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 7.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f).padding(end = 10.dp)) {
            txt(title)
            if (sub != null) txt(sub, 11.sp, muted())
        }
        Toggle(on, onChange)
    }
}

@Composable
fun SliderRow(
    label: String,
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    valueText: String,
    onChange: (Float) -> Unit,
    onFinish: () -> Unit = {},
) {
    val ui = LocalUi.current
    Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.SpaceBetween) {
        txt(label, color = muted())
        txt(valueText)
    }
    Slider(
        value = value, onValueChange = onChange, valueRange = range, onValueChangeFinished = onFinish,
        colors = SliderDefaults.colors(
            thumbColor = ui.accent, activeTrackColor = ui.accent, inactiveTrackColor = Color.White.copy(alpha = 0.2f),
        ),
    )
}

@Composable
fun Field(value: String, onChange: (String) -> Unit, hint: String, modifier: Modifier = Modifier, numeric: Boolean = false) {
    val shape = RoundedCornerShape(16.dp)
    Box(
        modifier.fillMaxWidth().padding(vertical = 4.dp).clip(shape).background(Color.Black.copy(alpha = 0.6f))
            .border(BorderStroke(0.6.dp, Color.White.copy(alpha = 0.18f)), shape).padding(horizontal = 14.dp, vertical = 14.dp),
    ) {
        if (value.isEmpty()) txt(hint, 13.sp, muted())
        BasicTextField(
            value = value, onValueChange = onChange, singleLine = true,
            textStyle = TextStyle(color = Paper, fontSize = 13.sp, fontFamily = Mono),
            cursorBrush = SolidColor(Paper),
            keyboardOptions = if (numeric) KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Number) else KeyboardOptions.Default,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@Composable
fun Chip(text: String, on: Boolean, onClick: () -> Unit) {
    val ui = LocalUi.current
    Box(
        Modifier.clip(CircleShape).background(if (on) ui.accent else Color.Transparent)
            .border(BorderStroke(0.6.dp, Color.White.copy(alpha = 0.25f)), CircleShape)
            .clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 6.dp),
    ) { txt(text, 11.sp, if (on) Ink else muted(), maxLines = 1) }
}

@Composable
fun BackBtn(onClick: () -> Unit) {
    Box(
        Modifier.padding(bottom = 10.dp).clip(CircleShape)
            .border(BorderStroke(0.6.dp, Color.White.copy(alpha = 0.25f)), CircleShape)
            .clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 9.dp),
    ) { txt("‹ KEMBALI", 12.sp, Paper, spacing = 1.2.sp) }
}

@Composable
fun Dot(on: Boolean) {
    Box(Modifier.size(8.dp).clip(CircleShape).background(if (on) Mint else Coral))
}

@Composable
fun StatusRow(name: String, on: Boolean, onText: String = "jalan", offText: String = "mati") {
    Row(Modifier.fillMaxWidth().padding(vertical = 7.dp), verticalAlignment = Alignment.CenterVertically) {
        txt(name, color = muted(), modifier = Modifier.weight(1f))
        Dot(on)
        Box(Modifier.width(6.dp))
        txt(if (on) onText else offText)
    }
}

// ---------- ikon app (dimuat di background, dikash) ----------
private val iconCache = HashMap<String, Bitmap>()

@Composable
fun AppIcon(pkg: String, size: Dp = 42.dp) {
    val ctx = LocalContext.current
    val bmp by produceState<Bitmap?>(iconCache[pkg], pkg) {
        if (value == null) {
            value = withContext(Dispatchers.IO) {
                try {
                    val b = ctx.packageManager.getApplicationIcon(pkg).toBitmap(96, 96)
                    iconCache[pkg] = b
                    b
                } catch (_: Exception) { null }
            }
        }
    }
    val shape = RoundedCornerShape(10.dp)
    val b = bmp
    if (b != null) {
        Image(b.asImageBitmap(), null, Modifier.size(size).clip(shape), contentScale = ContentScale.Crop)
    } else {
        Box(Modifier.size(size).clip(shape).background(Color.White.copy(alpha = 0.1f)))
    }
}
