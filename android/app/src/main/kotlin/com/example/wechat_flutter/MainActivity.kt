package com.example.wechat_flutter

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Canal usado pelas notificações push de "Nova mensagem" (importância
        // alta = aparece como aviso na tela, com som).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val canal = NotificationChannel(
                "mensagens",
                "Mensagens",
                NotificationManager.IMPORTANCE_HIGH
            )
            canal.description = "Avisos de novas mensagens"
            val gerenciador = getSystemService(NotificationManager::class.java)
            gerenciador.createNotificationChannel(canal)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Adicione códigos de canais nativos aqui se precisar no futuro
    }
}
