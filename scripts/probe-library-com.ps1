#requires -version 5.1
# Internal optional probe. No account, network or credential data is accessed.
$ErrorActionPreference='Stop'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class MusicComProbe {
    [DllImport("ole32.dll")] static extern int CoInitializeEx(IntPtr p, uint mode);
    [DllImport("ole32.dll")] static extern int CoCreateInstance(ref Guid clsid, IntPtr outer, uint ctx, ref Guid iid, out IntPtr result);
    [DllImport("ole32.dll")] static extern void CoUninitialize();
    public static int Run() {
        int init=CoInitializeEx(IntPtr.Zero,2);
        if(init<0) return init;
        IntPtr obj=IntPtr.Zero;
        try {
            Guid clsid=new Guid("68E7097C-F969-4006-AAC3-95115F0ED1C4");
            Guid iid=new Guid("00000000-0000-0000-C000-000000000046");
            return CoCreateInstance(ref clsid,IntPtr.Zero,4,ref iid,out obj);
        } finally { if(obj!=IntPtr.Zero) Marshal.Release(obj); CoUninitialize(); }
    }
}
"@
$hr=[MusicComProbe]::Run()
Write-Output ('Music Library COM HRESULT=0x{0:X8}' -f $hr)
if ($hr -lt 0) { exit 1 }