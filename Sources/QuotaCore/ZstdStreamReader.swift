// Streaming loop adapted from facebook/zstd v1.5.7 examples/streaming_decompression.c.
// Copyright (c) Meta Platforms, Inc. and affiliates.
// See Resources/ThirdPartyNotices/zstd-LICENSE.txt (BSD license).
import Foundation
import CZstd

enum ZstdStreamReader {
    enum ReadError: Error { case allocationFailed, corrupted, truncated }

    /// 逐块交付解压内容；校验全部帧后才返回，调用者不得缓存失败文件的半份结果。
    static func forEachChunk(in handle: FileHandle, consume: (Data) -> Void) throws {
        guard let context = ZSTD_createDCtx() else { throw ReadError.allocationFailed }
        defer { ZSTD_freeDCtx(context) }
        let capacity = 256 * 1024
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: capacity, alignment: 1)
        defer { buffer.deallocate() }
        // 空文件或未完整结束的帧都不能当作成功读取。
        var remaining = 1
        while let chunk = try handle.read(upToCount: capacity), !chunk.isEmpty {
            try chunk.withUnsafeBytes { bytes in
                var input = ZSTD_inBuffer(src: bytes.baseAddress, size: bytes.count, pos: 0)
                while input.pos < input.size {
                    var output = ZSTD_outBuffer(dst: buffer, size: capacity, pos: 0)
                    remaining = ZSTD_decompressStream(context, &output, &input)
                    guard ZSTD_isError(remaining) == 0 else { throw ReadError.corrupted }
                    if output.pos > 0 {
                        autoreleasepool { consume(Data(bytes: buffer, count: output.pos)) }
                    }
                    // 返回 0 仅表示一帧结束；继续读取后续拼接帧和 skippable 帧。
                }
            }
        }
        guard remaining == 0 else { throw ReadError.truncated }
    }
}
