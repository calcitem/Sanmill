#include "screenshot_plugin.h"

// This must be included before many other Windows headers.
#include <windows.h>
#include <wingdi.h>
#include <wincodec.h>
#include <windowsx.h>  // For GET_X_LPARAM and GET_Y_LPARAM

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>
#include <vector>

#pragma comment(lib, "windowscodecs.lib")

namespace screenshot {

// Helper function to encode HBITMAP to PNG bytes using WIC
std::vector<uint8_t> EncodeBitmapToPNG(HBITMAP hBitmap, int width, int height) {
  std::vector<uint8_t> pngBytes;
  
  // Initialize COM
  HRESULT hr = CoInitialize(nullptr);
  bool comInitialized = SUCCEEDED(hr);
  
  IWICImagingFactory* pFactory = nullptr;
  IWICBitmap* pWICBitmap = nullptr;
  IWICStream* pStream = nullptr;
  IWICBitmapEncoder* pEncoder = nullptr;
  IWICBitmapFrameEncode* pFrameEncode = nullptr;
  
  do {
    // Create WIC factory
    hr = CoCreateInstance(
      CLSID_WICImagingFactory,
      nullptr,
      CLSCTX_INPROC_SERVER,
      IID_IWICImagingFactory,
      reinterpret_cast<LPVOID*>(&pFactory)
    );
    if (FAILED(hr)) break;
    
    // Create WIC bitmap from HBITMAP
    hr = pFactory->CreateBitmapFromHBITMAP(hBitmap, nullptr, WICBitmapUseAlpha, &pWICBitmap);
    if (FAILED(hr)) break;
    
    // Create WIC stream
    hr = pFactory->CreateStream(&pStream);
    if (FAILED(hr)) break;
    
    // Create memory stream using IStream
    IStream* pMemStream = nullptr;
    hr = CreateStreamOnHGlobal(nullptr, TRUE, &pMemStream);
    if (FAILED(hr)) break;
    
    // Initialize WIC stream from IStream
    hr = pStream->InitializeFromIStream(pMemStream);
    pMemStream->Release();
    if (FAILED(hr)) break;
    
    // Create PNG encoder
    hr = pFactory->CreateEncoder(GUID_ContainerFormatPng, nullptr, &pEncoder);
    if (FAILED(hr)) break;
    
    hr = pEncoder->Initialize(pStream, WICBitmapEncoderNoCache);
    if (FAILED(hr)) break;
    
    // Create frame
    hr = pEncoder->CreateNewFrame(&pFrameEncode, nullptr);
    if (FAILED(hr)) break;
    
    hr = pFrameEncode->Initialize(nullptr);
    if (FAILED(hr)) break;
    
    hr = pFrameEncode->SetSize(width, height);
    if (FAILED(hr)) break;
    
    WICPixelFormatGUID formatGUID = GUID_WICPixelFormat32bppBGRA;
    hr = pFrameEncode->SetPixelFormat(&formatGUID);
    if (FAILED(hr)) break;
    
    hr = pFrameEncode->WriteSource(pWICBitmap, nullptr);
    if (FAILED(hr)) break;
    
    hr = pFrameEncode->Commit();
    if (FAILED(hr)) break;
    
    hr = pEncoder->Commit();
    if (FAILED(hr)) break;
    
    // Get data from stream
    ULARGE_INTEGER streamSize;
    IStream* pIStream = nullptr;
    hr = pStream->QueryInterface(IID_IStream, reinterpret_cast<void**>(&pIStream));
    if (SUCCEEDED(hr)) {
      STATSTG stat;
      if (SUCCEEDED(pIStream->Stat(&stat, STATFLAG_NONAME))) {
        streamSize = stat.cbSize;
        pngBytes.resize(static_cast<size_t>(streamSize.QuadPart));
        
        LARGE_INTEGER zero = {};
        pIStream->Seek(zero, STREAM_SEEK_SET, nullptr);
        
        ULONG bytesRead = 0;
        pIStream->Read(pngBytes.data(), static_cast<ULONG>(pngBytes.size()), &bytesRead);
      }
      pIStream->Release();
    }
    
  } while (false);
  
  // Cleanup
  if (pFrameEncode) pFrameEncode->Release();
  if (pEncoder) pEncoder->Release();
  if (pStream) pStream->Release();
  if (pWICBitmap) pWICBitmap->Release();
  if (pFactory) pFactory->Release();
  
  if (comInitialized) {
    CoUninitialize();
  }
  
  return pngBytes;
}

// Capture screen to HBITMAP
HBITMAP CaptureScreenToBitmap(int* width, int* height, bool includeCursor) {
  // Set DPI awareness
  SetProcessDPIAware();
  
  // Get screen DC
  HDC hdcScreen = GetDC(nullptr);
  if (!hdcScreen) return nullptr;
  
  // Get screen dimensions
  *width = GetSystemMetrics(SM_CXSCREEN);
  *height = GetSystemMetrics(SM_CYSCREEN);
  
  // Create compatible DC
  HDC hdcMemory = CreateCompatibleDC(hdcScreen);
  if (!hdcMemory) {
    ReleaseDC(nullptr, hdcScreen);
    return nullptr;
  }
  
  // Create compatible bitmap
  HBITMAP hBitmap = CreateCompatibleBitmap(hdcScreen, *width, *height);
  if (!hBitmap) {
    DeleteDC(hdcMemory);
    ReleaseDC(nullptr, hdcScreen);
    return nullptr;
  }
  
  // Select bitmap into memory DC
  HBITMAP hOldBitmap = static_cast<HBITMAP>(SelectObject(hdcMemory, hBitmap));
  
  // Copy screen to bitmap
  if (!BitBlt(hdcMemory, 0, 0, *width, *height, hdcScreen, 0, 0, SRCCOPY)) {
    SelectObject(hdcMemory, hOldBitmap);
    DeleteObject(hBitmap);
    DeleteDC(hdcMemory);
    ReleaseDC(nullptr, hdcScreen);
    return nullptr;
  }
  
  // Draw cursor if requested
  if (includeCursor) {
    CURSORINFO cursorInfo = {};
    cursorInfo.cbSize = sizeof(CURSORINFO);
    
    if (GetCursorInfo(&cursorInfo) && (cursorInfo.flags & CURSOR_SHOWING)) {
      ICONINFO iconInfo;
      if (GetIconInfo(cursorInfo.hCursor, &iconInfo)) {
        POINT pt;
        GetCursorPos(&pt);
        int x = pt.x - iconInfo.xHotspot;
        int y = pt.y - iconInfo.yHotspot;
        
        DrawIconEx(hdcMemory, x, y, cursorInfo.hCursor, 0, 0, 0, nullptr, DI_NORMAL);
        
        if (iconInfo.hbmMask) DeleteObject(iconInfo.hbmMask);
        if (iconInfo.hbmColor) DeleteObject(iconInfo.hbmColor);
      }
    }
  }
  
  // Restore old bitmap and cleanup DCs
  SelectObject(hdcMemory, hOldBitmap);
  DeleteDC(hdcMemory);
  ReleaseDC(nullptr, hdcScreen);
  
  return hBitmap;
}

// Structure to hold selection state
struct SelectionState {
  POINT startPoint;
  POINT currentPoint;
  bool isSelecting;
  bool cancelled;
  RECT selectedRect;
};

// Global state for overlay window (will be set during overlay creation)
static SelectionState* g_selectionState = nullptr;

// Window procedure for overlay window
LRESULT CALLBACK OverlayWndProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) {
  if (!g_selectionState) return DefWindowProc(hwnd, msg, wParam, lParam);
  
  switch (msg) {
    case WM_LBUTTONDOWN: {
      // Capture start point
      g_selectionState->startPoint.x = GET_X_LPARAM(lParam);
      g_selectionState->startPoint.y = GET_Y_LPARAM(lParam);
      g_selectionState->currentPoint = g_selectionState->startPoint;
      g_selectionState->isSelecting = true;
      SetCapture(hwnd);
      InvalidateRect(hwnd, nullptr, TRUE);
      return 0;
    }
    
    case WM_MOUSEMOVE: {
      if (g_selectionState->isSelecting) {
        // Update current point and redraw
        g_selectionState->currentPoint.x = GET_X_LPARAM(lParam);
        g_selectionState->currentPoint.y = GET_Y_LPARAM(lParam);
        InvalidateRect(hwnd, nullptr, TRUE);
      }
      return 0;
    }
    
    case WM_LBUTTONUP: {
      if (g_selectionState->isSelecting) {
        // Capture end point
        g_selectionState->currentPoint.x = GET_X_LPARAM(lParam);
        g_selectionState->currentPoint.y = GET_Y_LPARAM(lParam);
        g_selectionState->isSelecting = false;
        ReleaseCapture();
        
        // Normalize rectangle (handle reverse selection)
        int left = min(g_selectionState->startPoint.x, g_selectionState->currentPoint.x);
        int top = min(g_selectionState->startPoint.y, g_selectionState->currentPoint.y);
        int right = max(g_selectionState->startPoint.x, g_selectionState->currentPoint.x);
        int bottom = max(g_selectionState->startPoint.y, g_selectionState->currentPoint.y);
        
        g_selectionState->selectedRect.left = left;
        g_selectionState->selectedRect.top = top;
        g_selectionState->selectedRect.right = right;
        g_selectionState->selectedRect.bottom = bottom;
        
        // Close overlay
        DestroyWindow(hwnd);
      }
      return 0;
    }
    
    case WM_KEYDOWN: {
      if (wParam == VK_ESCAPE) {
        // User cancelled
        g_selectionState->cancelled = true;
        DestroyWindow(hwnd);
      }
      return 0;
    }
    
    case WM_RBUTTONDOWN: {
      // Right-click cancels
      g_selectionState->cancelled = true;
      DestroyWindow(hwnd);
      return 0;
    }
    
    case WM_ERASEBKGND:
      // Prevent default erase to avoid flicker
      return 1;
    
    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC hdc = BeginPaint(hwnd, &ps);
      
      // Get client area
      RECT clientRect;
      GetClientRect(hwnd, &clientRect);
      int width = clientRect.right - clientRect.left;
      int height = clientRect.bottom - clientRect.top;
      
      // Create double buffer
      HDC hdcMem = CreateCompatibleDC(hdc);
      HBITMAP hbmMem = CreateCompatibleBitmap(hdc, width, height);
      HBITMAP hbmOld = static_cast<HBITMAP>(SelectObject(hdcMem, hbmMem));
      
      // Fill background with semi-transparent black
      HBRUSH hBrush = CreateSolidBrush(RGB(0, 0, 0));
      FillRect(hdcMem, &clientRect, hBrush);
      DeleteObject(hBrush);
      
      // Draw selection rectangle if selecting
      if (g_selectionState->isSelecting || 
          (g_selectionState->selectedRect.right > g_selectionState->selectedRect.left)) {
        int left = min(g_selectionState->startPoint.x, g_selectionState->currentPoint.x);
        int top = min(g_selectionState->startPoint.y, g_selectionState->currentPoint.y);
        int right = max(g_selectionState->startPoint.x, g_selectionState->currentPoint.x);
        int bottom = max(g_selectionState->startPoint.y, g_selectionState->currentPoint.y);
        
        RECT selRect = {left, top, right, bottom};
        
        // Clear selection area (make it visible)
        HBRUSH hClearBrush = CreateSolidBrush(RGB(255, 255, 255));
        FillRect(hdcMem, &selRect, hClearBrush);
        DeleteObject(hClearBrush);
        
        // Draw border around selection
        HPEN hPen = CreatePen(PS_SOLID, 2, RGB(0, 120, 215)); // Blue border
        HPEN hOldPen = static_cast<HPEN>(SelectObject(hdcMem, hPen));
        SelectObject(hdcMem, GetStockObject(NULL_BRUSH));
        Rectangle(hdcMem, left, top, right, bottom);
        SelectObject(hdcMem, hOldPen);
        DeleteObject(hPen);
      }
      
      // Copy buffer to screen
      BitBlt(hdc, 0, 0, width, height, hdcMem, 0, 0, SRCCOPY);
      
      // Cleanup
      SelectObject(hdcMem, hbmOld);
      DeleteObject(hbmMem);
      DeleteDC(hdcMem);
      
      EndPaint(hwnd, &ps);
      return 0;
    }
    
    case WM_DESTROY:
      PostQuitMessage(0);
      return 0;
  }
  
  return DefWindowProc(hwnd, msg, wParam, lParam);
}

// Capture region with interactive overlay
HBITMAP CaptureRegionToBitmap(int* width, int* height, int* x, int* y, bool* cancelled) {
  *cancelled = false;
  
  // Set DPI awareness
  SetProcessDPIAware();
  
  // Get screen dimensions
  int screenWidth = GetSystemMetrics(SM_CXSCREEN);
  int screenHeight = GetSystemMetrics(SM_CYSCREEN);
  
  // Initialize selection state
  SelectionState state = {};
  state.isSelecting = false;
  state.cancelled = false;
  g_selectionState = &state;
  
  // Register window class
  const wchar_t* className = L"ScreenshotOverlayClass";
  WNDCLASSEX wc = {};
  wc.cbSize = sizeof(WNDCLASSEX);
  wc.style = CS_HREDRAW | CS_VREDRAW;
  wc.lpfnWndProc = OverlayWndProc;
  wc.hInstance = GetModuleHandle(nullptr);
  wc.hCursor = LoadCursor(nullptr, IDC_CROSS);
  wc.hbrBackground = static_cast<HBRUSH>(GetStockObject(BLACK_BRUSH));
  wc.lpszClassName = className;
  
  if (!RegisterClassEx(&wc)) {
    // Class might already be registered
    if (GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
      g_selectionState = nullptr;
      return nullptr;
    }
  }
  
  // Create fullscreen layered window
  HWND hwndOverlay = CreateWindowEx(
    WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW,
    className,
    L"Screenshot Overlay",
    WS_POPUP,
    0, 0, screenWidth, screenHeight,
    nullptr, nullptr, GetModuleHandle(nullptr), nullptr
  );
  
  if (!hwndOverlay) {
    UnregisterClass(className, GetModuleHandle(nullptr));
    g_selectionState = nullptr;
    return nullptr;
  }
  
  // Set semi-transparent background (50% opacity)
  SetLayeredWindowAttributes(hwndOverlay, 0, 128, LWA_ALPHA);
  
  // Show overlay
  ShowWindow(hwndOverlay, SW_SHOW);
  UpdateWindow(hwndOverlay);
  SetForegroundWindow(hwndOverlay);
  
  // Message loop
  MSG msg;
  while (GetMessage(&msg, nullptr, 0, 0)) {
    TranslateMessage(&msg);
    DispatchMessage(&msg);
  }
  
  // Cleanup window
  UnregisterClass(className, GetModuleHandle(nullptr));
  
  // Check if cancelled
  if (state.cancelled) {
    *cancelled = true;
    g_selectionState = nullptr;
    return nullptr;
  }
  
  // Validate selection
  int selWidth = state.selectedRect.right - state.selectedRect.left;
  int selHeight = state.selectedRect.bottom - state.selectedRect.top;
  
  if (selWidth <= 0 || selHeight <= 0) {
    // Invalid selection
    *cancelled = true;
    g_selectionState = nullptr;
    return nullptr;
  }
  
  // Capture the selected region
  HDC hdcScreen = GetDC(nullptr);
  if (!hdcScreen) {
    g_selectionState = nullptr;
    return nullptr;
  }
  
  HDC hdcMemory = CreateCompatibleDC(hdcScreen);
  if (!hdcMemory) {
    ReleaseDC(nullptr, hdcScreen);
    g_selectionState = nullptr;
    return nullptr;
  }
  
  HBITMAP hBitmap = CreateCompatibleBitmap(hdcScreen, selWidth, selHeight);
  if (!hBitmap) {
    DeleteDC(hdcMemory);
    ReleaseDC(nullptr, hdcScreen);
    g_selectionState = nullptr;
    return nullptr;
  }
  
  HBITMAP hOldBitmap = static_cast<HBITMAP>(SelectObject(hdcMemory, hBitmap));
  
  // Copy selected region to bitmap
  if (!BitBlt(hdcMemory, 0, 0, selWidth, selHeight, hdcScreen, 
              state.selectedRect.left, state.selectedRect.top, SRCCOPY)) {
    SelectObject(hdcMemory, hOldBitmap);
    DeleteObject(hBitmap);
    DeleteDC(hdcMemory);
    ReleaseDC(nullptr, hdcScreen);
    g_selectionState = nullptr;
    return nullptr;
  }
  
  // Restore and cleanup
  SelectObject(hdcMemory, hOldBitmap);
  DeleteDC(hdcMemory);
  ReleaseDC(nullptr, hdcScreen);
  
  // Set output parameters
  *width = selWidth;
  *height = selHeight;
  *x = state.selectedRect.left;
  *y = state.selectedRect.top;
  
  g_selectionState = nullptr;
  return hBitmap;
}

// static
void ScreenshotPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto channel =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "dev.flutter.screenshot",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<ScreenshotPlugin>();

  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto &call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

ScreenshotPlugin::ScreenshotPlugin() {}

ScreenshotPlugin::~ScreenshotPlugin() {}

void ScreenshotPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  if (method_call.method_name().compare("capture") == 0) {
    // Extract parameters
    const auto* arguments = std::get_if<flutter::EncodableMap>(method_call.arguments());
    if (!arguments) {
      result->Error("invalid_argument", "Arguments must be a map");
      return;
    }
    
    // Get mode parameter
    auto mode_it = arguments->find(flutter::EncodableValue("mode"));
    if (mode_it == arguments->end()) {
      result->Error("invalid_argument", "Missing 'mode' parameter");
      return;
    }
    
    const auto* mode_str = std::get_if<std::string>(&mode_it->second);
    if (!mode_str) {
      result->Error("invalid_argument", "'mode' must be a string");
      return;
    }
    
    // Validate mode
    if (*mode_str != "screen" && *mode_str != "region") {
      result->Error("invalid_argument", "Invalid mode: " + *mode_str);
      return;
    }
    
    // Get includeCursor parameter (optional, default false)
    bool includeCursor = false;
    auto cursor_it = arguments->find(flutter::EncodableValue("includeCursor"));
    if (cursor_it != arguments->end()) {
      const auto* cursor_bool = std::get_if<bool>(&cursor_it->second);
      if (cursor_bool) {
        includeCursor = *cursor_bool;
      }
    }
    
    // Only implement screen mode for now (US1)
    if (*mode_str == "screen") {
      int width = 0;
      int height = 0;
      
      // Capture screen to bitmap
      HBITMAP hBitmap = CaptureScreenToBitmap(&width, &height, includeCursor);
      if (!hBitmap) {
        result->Error("internal_error", "Failed to capture screen", 
                     flutter::EncodableValue(static_cast<int>(GetLastError())));
        return;
      }
      
      // Encode to PNG
      std::vector<uint8_t> pngBytes = EncodeBitmapToPNG(hBitmap, width, height);
      DeleteObject(hBitmap);
      
      if (pngBytes.empty()) {
        result->Error("internal_error", "Failed to encode PNG");
        return;
      }
      
      // Create result map
      flutter::EncodableMap resultMap;
      resultMap[flutter::EncodableValue("width")] = flutter::EncodableValue(width);
      resultMap[flutter::EncodableValue("height")] = flutter::EncodableValue(height);
      resultMap[flutter::EncodableValue("bytes")] = flutter::EncodableValue(pngBytes);
      
      result->Success(flutter::EncodableValue(resultMap));
    } else if (*mode_str == "region") {
      // Region mode (US2)
      int width = 0;
      int height = 0;
      int x = 0;
      int y = 0;
      bool cancelled = false;
      
      // Capture region with overlay
      HBITMAP hBitmap = CaptureRegionToBitmap(&width, &height, &x, &y, &cancelled);
      
      if (cancelled || !hBitmap) {
        // User cancelled or invalid selection - return null
        result->Success();  // Success with null value
        return;
      }
      
      // Encode to PNG
      std::vector<uint8_t> pngBytes = EncodeBitmapToPNG(hBitmap, width, height);
      DeleteObject(hBitmap);
      
      if (pngBytes.empty()) {
        result->Error("internal_error", "Failed to encode PNG");
        return;
      }
      
      // Create result map
      flutter::EncodableMap resultMap;
      resultMap[flutter::EncodableValue("width")] = flutter::EncodableValue(width);
      resultMap[flutter::EncodableValue("height")] = flutter::EncodableValue(height);
      resultMap[flutter::EncodableValue("bytes")] = flutter::EncodableValue(pngBytes);
      
      result->Success(flutter::EncodableValue(resultMap));
    } else {
      // Unknown mode
      result->Error("invalid_argument", "Invalid mode: " + *mode_str);
    }
  } else {
    result->NotImplemented();
  }
}

}  // namespace screenshot
