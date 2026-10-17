"""Package an experimental, unsigned adapter IPA without rewriting UI resources.

Usage: python repack.py ORIGINAL.ipa DSAPIAdapter.dylib OUTPUT.ipa
This verifies package integrity and unchanged resources, not runtime behavior.
"""
import hashlib
import copy
import json
import plistlib
import struct
import sys
import zipfile
from pathlib import Path


def digest(data):
    return hashlib.sha256(data).hexdigest()


def add_library(binary, name):
    if binary[:4] != b'\xcf\xfa\xed\xfe':
        raise ValueError('Expected the known thin 64-bit Mach-O')
    count, size = struct.unpack_from('<II', binary, 16)
    end = 32 + size
    if end > len(binary):
        raise ValueError('Invalid load-command bounds')
    cursor = 32
    first_section = len(binary)
    code_ranges = []
    for _ in range(count):
        command, length = struct.unpack_from('<II', binary, cursor)
        if length < 8 or cursor + length > end:
            raise ValueError('Invalid load command')
        if command in (0xc, 0x80000018, 0x8000001f):
            offset = struct.unpack_from('<I', binary, cursor + 8)[0]
            old_name = binary[cursor + offset:cursor + length].split(b'\0')[0].decode()
            if old_name == name:
                raise ValueError('Input already contains the adapter')
        if command == 0x19:
            segment = binary[cursor+8:cursor+24].rstrip(b'\0')
            section_count = struct.unpack_from('<I', binary, cursor + 64)[0]
            for index in range(section_count):
                section = cursor + 72 + index * 80
                section_name = binary[section:section+16].rstrip(b'\0')
                length_bytes, file_offset = struct.unpack_from('<QI', binary, section + 40)
                flags = struct.unpack_from('<I', binary, section + 64)[0]
                section_type = flags & 0xff
                if file_offset and length_bytes and section_type not in (1, 0xc, 0x12):
                    first_section = min(first_section,file_offset)
                    if segment == b'__TEXT':
                        code_ranges.append((section_name,file_offset,length_bytes))
        cursor += length
    if cursor != end:
        raise ValueError('Load-command count/size mismatch')
    encoded = name.encode() + b'\0'
    command_size = (24 + len(encoded) + 7) & ~7
    if end + command_size > first_section or any(binary[end:end+command_size]):
        raise ValueError('No verified zero header padding; refusing to relocate original code')
    command = struct.pack('<6I',0xc,command_size,24,0,0x10000,0x10000) + encoded
    command = command.ljust(command_size,b'\0')
    output = bytearray(binary)
    output[end:end+command_size] = command
    struct.pack_into('<II',output,16,count+1,size+command_size)
    for section,offset,length in code_ranges:
        if binary[offset:offset+length] != output[offset:offset+length]:
            raise ValueError(f'Original TEXT section changed: {section!r}')
    return bytes(output),len(code_ranges)


def main():
    source, library, destination = map(Path,sys.argv[1:])
    if source.resolve() == destination.resolve():
        raise ValueError('Never overwrite the original IPA')
    module = library.read_bytes()
    if module[:4] != b'\xcf\xfa\xed\xfe':
        raise ValueError('Adapter is not a thin Mach-O dylib')
    if struct.unpack_from('<I',module,4)[0] != 0x100000c or struct.unpack_from('<I',module,12)[0] != 6:
        raise ValueError('Adapter must be an arm64 Mach-O dylib')
    expected_original = '92a96bbbb7938f084a3840b4426bd891fe18dc46c1b6d4221186cb7df6cc18d9'
    if digest(source.read_bytes()) != expected_original:
        raise ValueError('Original IPA identity differs from the analyzed input')
    with zipfile.ZipFile(source) as original:
        names = original.namelist()
        if len(names) != len(set(names)):
            raise ValueError('Duplicate ZIP entries')
        info_name = 'Payload/DeepSeek Chat.app/Info.plist'
        info = plistlib.loads(original.read(info_name))
        if info.get('CFBundleIdentifier') != 'com.deepseek.chat' or info.get('CFBundleShortVersionString') != '2.6.2':
            raise ValueError('Unexpected application identity')
        root = info_name.rsplit('/',1)[0]+'/'
        executable = root+info['CFBundleExecutable']
        target = root+'Frameworks/DSAPIAdapter.dylib'
        if target in names:
            raise ValueError('Adapter already present')
        patched, sections = add_library(original.read(executable),'@executable_path/Frameworks/DSAPIAdapter.dylib')
        with zipfile.ZipFile(destination,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as output:
            for item in original.infolist():
                # Signing is deliberately left to the user's signing tool.
                if '/_CodeSignature/' in item.filename or item.filename.endswith('/embedded.mobileprovision'):
                    continue
                # ZipFile.writestr mutates ZipInfo.header_offset. Preserve the input
                # archive's offsets for the independent resource comparison below.
                output.writestr(copy.copy(item),patched if item.filename == executable else original.read(item))
            item = zipfile.ZipInfo(target)
            item.compress_type = zipfile.ZIP_DEFLATED
            item.external_attr = 0o100755 << 16
            output.writestr(item,module)
        preserved = 0
        with zipfile.ZipFile(destination) as output:
            if output.testzip() is not None:
                raise ValueError('Output ZIP integrity failed')
            for item in output.infolist():
                if item.filename in (executable,target):
                    continue
                if digest(output.read(item)) != digest(original.read(item.filename)):
                    raise ValueError('Original resource changed: '+item.filename)
                preserved += 1
    report = {'status':'experimental-unsigned-integration-candidate',
        'original_sha256':expected_original,'adapter_sha256':digest(module),
        'ipa_sha256':digest(destination.read_bytes()),'ipa_bytes':destination.stat().st_size,
        'unchanged_original_entries':preserved,'unchanged_original_TEXT_sections':sections,
        'runtime_verified':False,'login_code_physically_removed':False,
        'not_verified':['startup','UI equivalence','API requests','original event decoding','device installation','widgets'],
        'unsupported':['attachments','original search backend','voice','cloud sharing']}
    destination.with_suffix('.verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2))
    print(json.dumps(report,ensure_ascii=False,indent=2))


if __name__ == '__main__':
    main()
