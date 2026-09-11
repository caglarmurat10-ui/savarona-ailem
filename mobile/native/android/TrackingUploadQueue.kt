package com.savarona.ailem

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import org.json.JSONObject

class TrackingUploadQueue(context: Context) : SQLiteOpenHelper(context.applicationContext, "savarona_tracking_queue.db", null, 1) {
    companion object { private const val TABLE = "queue"; const val MAX_ROWS = 500 }

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL("""
            CREATE TABLE $TABLE (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                sequence_no INTEGER NOT NULL,
                captured_at INTEGER NOT NULL,
                lat REAL NOT NULL,
                lng REAL NOT NULL,
                accuracy_m REAL,
                speed_mps REAL,
                heading_deg REAL,
                battery_pct INTEGER,
                activity TEXT
            )
        """.trimIndent())
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        db.execSQL("DROP TABLE IF EXISTS $TABLE")
        onCreate(db)
    }

    @Synchronized fun enqueue(sample: LocationSample) {
        writableDatabase.use { db ->
            db.insert(TABLE, null, ContentValues().apply {
                put("sequence_no", sample.sequenceNo); put("captured_at", sample.capturedAt)
                put("lat", sample.lat); put("lng", sample.lng); put("accuracy_m", sample.accuracyM)
                put("speed_mps", sample.speedMps); put("heading_deg", sample.headingDeg)
                put("battery_pct", sample.batteryPct); put("activity", sample.activity)
            })
            db.execSQL("DELETE FROM $TABLE WHERE id NOT IN (SELECT id FROM $TABLE ORDER BY id DESC LIMIT ?)", arrayOf(MAX_ROWS.toString()))
        }
    }

    @Synchronized fun peekOldest(): QueuedSample? {
        readableDatabase.rawQuery("SELECT id,sequence_no,captured_at,lat,lng,accuracy_m,speed_mps,heading_deg,battery_pct,activity FROM $TABLE ORDER BY id ASC LIMIT 1", null).use { c ->
            if (!c.moveToFirst()) return null
            return QueuedSample(c.getLong(0),c.getLong(1),c.getLong(2),c.getDouble(3),c.getDouble(4),
                if(c.isNull(5)) null else c.getDouble(5), if(c.isNull(6)) null else c.getDouble(6),
                if(c.isNull(7)) null else c.getDouble(7), if(c.isNull(8)) null else c.getInt(8), if(c.isNull(9)) null else c.getString(9))
        }
    }
    @Synchronized fun remove(rowId: Long) { writableDatabase.use { it.delete(TABLE, "id=?", arrayOf(rowId.toString())) } }
    @Synchronized fun count(): Int { readableDatabase.rawQuery("SELECT COUNT(*) FROM $TABLE", null).use { it.moveToFirst(); return it.getInt(0) } }
}

data class LocationSample(val sequenceNo:Long,val capturedAt:Long,val lat:Double,val lng:Double,val accuracyM:Double?,val speedMps:Double?,val headingDeg:Double?,val batteryPct:Int?,val activity:String?)
data class QueuedSample(val rowId:Long,val sequenceNo:Long,val capturedAt:Long,val lat:Double,val lng:Double,val accuracyM:Double?,val speedMps:Double?,val headingDeg:Double?,val batteryPct:Int?,val activity:String?) {
    fun isUsable(): Boolean = lat.isFinite() && lng.isFinite() && lat in -90.0..90.0 && lng in -180.0..180.0
    fun toJson(): String = JSONObject().apply {
        put("sequence_no",sequenceNo); put("captured_at",capturedAt); put("lat",lat); put("lng",lng)
        if(accuracyM?.isFinite()==true) put("accuracy_m",accuracyM); if(speedMps?.isFinite()==true) put("speed_mps",speedMps)
        if(headingDeg?.isFinite()==true) put("heading_deg",headingDeg); if(batteryPct!=null) put("battery_pct",batteryPct); if(activity!=null) put("activity",activity)
    }.toString()
}
