package com.moondev.drive.moondrive;

import android.content.ContentValues;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.MediaStore;

import androidx.annotation.NonNull;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
	private static final String CHANNEL = "moondrive/android_storage";

	@Override
	public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
		super.configureFlutterEngine(flutterEngine);
		new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
				.setMethodCallHandler((call, result) -> {
					switch (call.method) {
						case "saveToPublicDownloads":
							handleSaveToPublicDownloads(call, result);
							break;
						case "openUri":
							handleOpenUri(call, result);
							break;
						default:
							result.notImplemented();
					}
				});
	}

	private void handleSaveToPublicDownloads(MethodCall call, MethodChannel.Result result) {
		final String sourcePath = call.argument("sourcePath");
		final String fileName = call.argument("fileName");
		final String mimeType = call.argument("mimeType");
		final String folderName = call.argument("folderName");

		if (sourcePath == null || fileName == null || fileName.trim().isEmpty()) {
			result.error("invalid_args", "sourcePath and fileName are required.", null);
			return;
		}

		final String safeFileName = fileName.trim();
		final String safeFolderName = folderName == null || folderName.trim().isEmpty()
				? "MoonDrive Downloads"
				: folderName.trim();

		try {
			final File sourceFile = new File(sourcePath);
			if (!sourceFile.exists()) {
				result.error("missing_file", "Source file does not exist.", null);
				return;
			}

			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
				final android.content.ContentResolver resolver = getApplicationContext().getContentResolver();
				final ContentValues values = new ContentValues();
				values.put(MediaStore.MediaColumns.DISPLAY_NAME, safeFileName);
				values.put(MediaStore.MediaColumns.MIME_TYPE,
						mimeType == null || mimeType.trim().isEmpty() ? "application/octet-stream" : mimeType);
				values.put(MediaStore.MediaColumns.RELATIVE_PATH,
						Environment.DIRECTORY_DOWNLOADS + File.separator + safeFolderName);
				values.put(MediaStore.MediaColumns.IS_PENDING, 1);

				final Uri collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY);
				final Uri itemUri = resolver.insert(collection, values);
				if (itemUri == null) {
					result.error("insert_failed", "Could not create destination file.", null);
					return;
				}

				try (InputStream in = new FileInputStream(sourceFile);
					 OutputStream out = resolver.openOutputStream(itemUri, "w")) {
					if (out == null) {
						resolver.delete(itemUri, null, null);
						result.error("open_stream_failed", "Could not open destination stream.", null);
						return;
					}

					byte[] buffer = new byte[8192];
					int read;
					while ((read = in.read(buffer)) != -1) {
						out.write(buffer, 0, read);
					}
					out.flush();
				}

				ContentValues doneValues = new ContentValues();
				doneValues.put(MediaStore.MediaColumns.IS_PENDING, 0);
				resolver.update(itemUri, doneValues, null, null);
				result.success(itemUri.toString());
				return;
			}

			File downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS);
			File targetDir = new File(downloadsDir, safeFolderName);
			if (!targetDir.exists() && !targetDir.mkdirs()) {
				result.error("mkdir_failed", "Could not create Downloads folder.", null);
				return;
			}

			File targetFile = new File(targetDir, safeFileName);
			try (InputStream in = new FileInputStream(sourceFile);
				 OutputStream out = new java.io.FileOutputStream(targetFile)) {
				byte[] buffer = new byte[8192];
				int read;
				while ((read = in.read(buffer)) != -1) {
					out.write(buffer, 0, read);
				}
				out.flush();
			}
			result.success(targetFile.getAbsolutePath());
		} catch (IOException e) {
			result.error("io_error", e.getMessage(), null);
		}
	}

	private void handleOpenUri(MethodCall call, MethodChannel.Result result) {
		final String uriString = call.argument("uri");
		final String mimeType = call.argument("mimeType");
		if (uriString == null || uriString.trim().isEmpty()) {
			result.error("invalid_args", "uri is required.", null);
			return;
		}

		try {
			Uri uri = Uri.parse(uriString);
			Intent intent = new Intent(Intent.ACTION_VIEW);
			intent.setDataAndType(uri, mimeType == null || mimeType.trim().isEmpty()
					? "application/octet-stream"
					: mimeType);
			intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
			intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
			startActivity(intent);
			result.success("done");
		} catch (Exception e) {
			result.error("open_failed", e.getMessage(), null);
		}
	}
}

