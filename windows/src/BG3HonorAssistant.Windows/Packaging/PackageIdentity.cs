using System.Runtime.InteropServices;

namespace BG3HonorAssistant.Windows.Packaging;

public static class PackageIdentity
{
    private const int AppModelErrorNoPackage = 15700;
    private const int ErrorInsufficientBuffer = 122;

    public static unsafe bool IsPackaged
    {
        get
        {
            uint length = 0;
            var result = PackageIdentityNativeMethods.GetCurrentPackageFullName(
                ref length,
                null);
            return result is ErrorInsufficientBuffer or 0;
        }
    }

    public static unsafe string? TryGetFullName()
    {
        return ReadPackageIdentity(PackageIdentityNativeMethods.GetCurrentPackageFullName);
    }

    public static unsafe string? TryGetFamilyName()
    {
        return ReadPackageIdentity(PackageIdentityNativeMethods.GetCurrentPackageFamilyName);
    }

    private static unsafe string? ReadPackageIdentity(PackageIdentityReader reader)
    {
        uint length = 0;
        var result = reader(ref length, null);
        if (result == AppModelErrorNoPackage)
        {
            return null;
        }

        if (result != ErrorInsufficientBuffer && result != 0)
        {
            Marshal.ThrowExceptionForHR(HResultFromWin32(result));
        }

        var name = new char[checked((int)length)];
        fixed (char* namePointer = name)
        {
            result = reader(ref length, namePointer);
            if (result != 0)
            {
                Marshal.ThrowExceptionForHR(HResultFromWin32(result));
            }
        }

        var contentLength = Array.IndexOf(name, '\0');
        return new string(name, 0, contentLength < 0 ? name.Length : contentLength);
    }

    private unsafe delegate int PackageIdentityReader(
        ref uint packageIdentityLength,
        char* packageIdentity);

    private static int HResultFromWin32(int error)
    {
        return error <= 0
            ? error
            : unchecked((int)(0x80070000U | (uint)error));
    }
}

internal static partial class PackageIdentityNativeMethods
{
    [LibraryImport("kernel32.dll", EntryPoint = "GetCurrentPackageFullName")]
    internal static unsafe partial int GetCurrentPackageFullName(
        ref uint packageFullNameLength,
        char* packageFullName);

    [LibraryImport("kernel32.dll", EntryPoint = "GetCurrentPackageFamilyName")]
    internal static unsafe partial int GetCurrentPackageFamilyName(
        ref uint packageFamilyNameLength,
        char* packageFamilyName);
}
