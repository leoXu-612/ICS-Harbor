// Read-only probe. It never opens or changes the game's configuration.
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Web.Script.Serialization;

class HarborDisplayProbe {
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int left, top, right, bottom; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct OutputDesc {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string name;
        public Rect bounds; public int attached, rotation; public IntPtr monitor;
    }
    [StructLayout(LayoutKind.Sequential)] struct MonitorInfo {
        public int size; public Rect monitor, work; public uint flags;
    }
    [StructLayout(LayoutKind.Sequential)] struct Luid { public uint low; public int high; }
    [StructLayout(LayoutKind.Sequential)] struct PathSource { public Luid adapter; public uint id, mode, flags; }
    [StructLayout(LayoutKind.Sequential)] struct PathTarget {
        public Luid adapter; public uint id, mode, technology, rotation, scaling, numerator, denominator, scan;
        public int available; public uint flags;
    }
    [StructLayout(LayoutKind.Sequential)] struct DisplayPath { public PathSource source; public PathTarget target; public uint flags; }
    [StructLayout(LayoutKind.Sequential)] struct Header { public uint type, size; public Luid adapter; public uint id; }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct SourceName {
        public Header header;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=32)] public string name;
    }
    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct TargetName {
        public Header header; public uint flags, technology; public ushort manufacturer, product; public uint connector;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=64)] public string friendlyName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst=128)] public string devicePath;
    }
    [DllImport("user32.dll")] static extern int GetDisplayConfigBufferSizes(uint flags, out uint paths, out uint modes);
    [DllImport("user32.dll")] static extern int QueryDisplayConfig(uint flags, ref uint paths, IntPtr pathBuffer, ref uint modes, IntPtr modeBuffer, IntPtr topology);
    [DllImport("user32.dll", EntryPoint="DisplayConfigGetDeviceInfo")] static extern int SourceInfo(ref SourceName name);
    [DllImport("user32.dll", EntryPoint="DisplayConfigGetDeviceInfo")] static extern int TargetInfo(ref TargetName name);
    [DllImport("dxgi.dll")] static extern int CreateDXGIFactory1(ref Guid id, out IntPtr factory);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int Enumerate(IntPtr self, uint index, out IntPtr result);
    [UnmanagedFunctionPointer(CallingConvention.StdCall)] delegate int GetDescription(IntPtr self, out OutputDesc result);
    static T Method<T>(IntPtr obj, int slot) {
        return (T)(object)Marshal.GetDelegateForFunctionPointer(Marshal.ReadIntPtr(Marshal.ReadIntPtr(obj), slot * IntPtr.Size), typeof(T));
    }
    // The modern display API supplies the EDID/model name NieR persists.
    // EnumDisplayDevices.description only returns a generic PnP driver label.
    static string FriendlyName(string gdiName) {
        uint pathCount, modeCount;
        if (GetDisplayConfigBufferSizes(2, out pathCount, out modeCount) != 0 || pathCount == 0 || pathCount > 128 || modeCount > 512)
            throw new Exception("Display configuration unavailable");
        int stride = Marshal.SizeOf(typeof(DisplayPath));
        IntPtr paths = Marshal.AllocHGlobal((int)pathCount * stride);
        IntPtr modes = Marshal.AllocHGlobal((int)modeCount * 64); // DISPLAYCONFIG_MODE_INFO
        try {
            if (QueryDisplayConfig(2, ref pathCount, paths, ref modeCount, modes, IntPtr.Zero) != 0)
                throw new Exception("Display configuration changed while checking; retry");
            string selected = null;
            for (int i = 0; i < pathCount; i++) {
                DisplayPath path = (DisplayPath)Marshal.PtrToStructure(IntPtr.Add(paths, i * stride), typeof(DisplayPath));
                if (path.target.available == 0) continue;
                SourceName source = new SourceName();
                source.header = new Header { type=1, size=(uint)Marshal.SizeOf(typeof(SourceName)), adapter=path.source.adapter, id=path.source.id };
                if (SourceInfo(ref source) != 0) throw new Exception("Display source query failed; no configuration changed");
                if (source.name != gdiName) continue;
                TargetName target = new TargetName();
                target.header = new Header { type=2, size=(uint)Marshal.SizeOf(typeof(TargetName)), adapter=path.target.adapter, id=path.target.id };
                if (TargetInfo(ref target) != 0 || String.IsNullOrWhiteSpace(target.friendlyName))
                    throw new Exception("Physical display name unavailable");
                if (selected != null) throw new Exception("Mirrored output is ambiguous; no configuration changed");
                selected = target.friendlyName.Trim();
            }
            if (selected == null) throw new Exception("Primary output not found in active display paths");
            return selected;
        } finally { Marshal.FreeHGlobal(paths); Marshal.FreeHGlobal(modes); }
    }
    static object Inspect() {
        Guid id = new Guid("7b7166ec-21c7-44ae-b21a-c9ae321ae369"); IntPtr factory;
        Marshal.ThrowExceptionForHR(CreateDXGIFactory1(ref id, out factory));
        object selected = null;
        try {
            // NieR uses the first graphics adapter. Query the same DXGI output list.
            IntPtr adapter; Marshal.ThrowExceptionForHR(Method<Enumerate>(factory, 7)(factory, 0, out adapter));
            try {
                for (uint index = 0; index < 32; index++) {
                    IntPtr output; int hr = Method<Enumerate>(adapter, 7)(adapter, index, out output);
                    if (hr == unchecked((int)0x887A0002)) break;
                    Marshal.ThrowExceptionForHR(hr);
                    try {
                        OutputDesc desc; Marshal.ThrowExceptionForHR(Method<GetDescription>(output, 7)(output, out desc));
                        MonitorInfo info = new MonitorInfo(); info.size = Marshal.SizeOf(typeof(MonitorInfo));
                        if (desc.attached == 0 || !GetMonitorInfo(desc.monitor, ref info) || (info.flags & 1) == 0) continue;
                        if (selected != null) throw new Exception("Multiple primary outputs reported");
                        string friendlyName = FriendlyName(desc.name);
                        string documents = Environment.GetFolderPath(Environment.SpecialFolder.MyDocuments);
                        if (String.IsNullOrWhiteSpace(documents)) throw new Exception("Documents path unavailable");
                        selected = new { documentsPath = documents, outputIndex = index, outputName = friendlyName };
                    } finally { Marshal.Release(output); }
                }
            } finally { Marshal.Release(adapter); }
        } finally { Marshal.Release(factory); }
        if (selected == null) throw new Exception("No primary output reported");
        return selected;
    }
    static int Main() {
        try {
            string json = new JavaScriptSerializer().Serialize(Inspect());
            File.WriteAllText("report.json.tmp", json, new UTF8Encoding(false));
            File.Move("report.json.tmp", "report.json");
            return 0;
        } catch (Exception error) {
            File.WriteAllText("probe-error.txt", error.Message, new UTF8Encoding(false));
            return 1;
        }
    }
}
