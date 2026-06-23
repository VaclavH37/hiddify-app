package com.raynlabs.app.ktx

import android.net.IpPrefix
import android.os.Build
import androidx.annotation.RequiresApi
import com.raynlabs.core.libbox.RoutePrefix
import com.raynlabs.core.libbox.StringIterator
import com.raynlabs.core.libbox.StringBox
import java.net.InetAddress

val StringBox?.unwrap: String
get() {
    if (this == null) return ""
    return value
}

fun StringIterator.toList(): List<String> {
    return mutableListOf<String>().apply {
        while (hasNext()) {
            add(next())
        }
    }
}

@RequiresApi(Build.VERSION_CODES.TIRAMISU)
fun RoutePrefix.toIpPrefix() = IpPrefix(InetAddress.getByName(address()), prefix())