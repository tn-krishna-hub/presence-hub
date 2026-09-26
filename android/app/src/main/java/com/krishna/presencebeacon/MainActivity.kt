package com.krishna.presencebeacon

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.Button
import android.widget.Spinner
import android.widget.TextView
import android.widget.Toast

class MainActivity : Activity() {

    private val identity by lazy { IdentityStore(this).uuid() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        findViewById<TextView>(R.id.identity).text = identity.toString()

        findViewById<Button>(R.id.copy).setOnClickListener {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            clipboard.setPrimaryClip(ClipData.newPlainText("identity", identity.toString()))
            Toast.makeText(this, R.string.copied, Toast.LENGTH_SHORT).show()
        }

        findViewById<Button>(R.id.start).setOnClickListener { startBeacon() }
        findViewById<Button>(R.id.stop).setOnClickListener {
            startService(Intent(this, BeaconService::class.java).setAction(Constants.ACTION_STOP))
            updateStatus()
        }
        findViewById<Button>(R.id.refresh).setOnClickListener { updateStatus() }

        setupTxPowerSpinner()

        requestNeededPermissions()
        updateStatus()
    }

    private fun setupTxPowerSpinner() {
        val settings = BeaconSettingsStore(this)
        val spinner = findViewById<Spinner>(R.id.tx_power)
        val powers = BeaconAdvertiser.TxPower.entries
        spinner.adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_item,
            powers.map { it.label }
        ).apply { setDropDownViewResource(android.R.layout.simple_spinner_dropdown_item) }
        spinner.setSelection(powers.indexOfFirst { it == settings.txPower })
        spinner.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                settings.txPower = powers[position]
            }
            override fun onNothingSelected(parent: AdapterView<*>?) = Unit
        }
    }

    override fun onResume() {
        super.onResume()
        updateStatus()
    }

    override fun onStart() {
        super.onStart()
        statusTicker()
    }

    override fun onStop() {
        super.onStop()
        ticker?.removeCallbacksAndMessages(null)
    }

    private var ticker: Handler? = null

    private fun statusTicker() {
        val handler = Handler(Looper.getMainLooper())
        ticker = handler
        handler.post(object : Runnable {
            override fun run() {
                if (isFinishing) return
                updateStatus()
                handler.postDelayed(this, 1500)
            }
        })
    }

    private fun startBeacon() {
        val intent = Intent(this, BeaconService::class.java).setAction(Constants.ACTION_START)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            @Suppress("DEPRECATION") startService(intent)
        }
        updateStatus()
    }

    private fun updateStatus() {
        val status = findViewById<TextView>(R.id.status)
        val adapter = runCatching {
            (getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
        }.getOrNull()
        val lines = mutableListOf<String>()
        when {
            adapter == null -> lines += getString(R.string.status_no_bluetooth)
            !adapter.isEnabled -> lines += getString(R.string.status_bluetooth_off)
            else -> lines += getString(R.string.status_ready)
        }
        lines += beaconStatusLine()
        status.text = lines.joinToString("\n")
        status.setTextColor(
            when (BeaconService.advertisingStatus) {
                BeaconService.AdvertisingStatus.BROADCASTING -> 0xFF4CAF50.toInt()
                BeaconService.AdvertisingStatus.FAILED,
                BeaconService.AdvertisingStatus.UNAVAILABLE -> 0xFFF44336.toInt()
                else -> 0xFF9E9E9E.toInt()
            }
        )
    }

    private fun beaconStatusLine(): String =
        when (BeaconService.advertisingStatus) {
            BeaconService.AdvertisingStatus.BROADCASTING ->
                getString(R.string.beacon_broadcasting)
            BeaconService.AdvertisingStatus.FAILED ->
                getString(R.string.beacon_failed, BeaconService.lastFailureCode)
            BeaconService.AdvertisingStatus.STARTING ->
                getString(R.string.beacon_starting)
            BeaconService.AdvertisingStatus.UNAVAILABLE ->
                getString(R.string.beacon_no_bluetooth)
            BeaconService.AdvertisingStatus.IDLE ->
                getString(R.string.beacon_idle)
        }

    private fun requestNeededPermissions() {
        val needed = mutableListOf<String>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            needed += Manifest.permission.BLUETOOTH_ADVERTISE
            needed += Manifest.permission.BLUETOOTH_CONNECT
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            needed += Manifest.permission.POST_NOTIFICATIONS
        }
        val missing = needed.filter {
            checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED
        }
        if (missing.isNotEmpty()) {
            requestPermissions(missing.toTypedArray(), REQUEST_PERMISSIONS)
        }
    }

    private companion object {
        const val REQUEST_PERMISSIONS = 42
    }
}