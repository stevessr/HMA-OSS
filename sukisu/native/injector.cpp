// AArch64-only standalone SukiSU development backend.
// ptrace calls are guarded: restore the original thread context on every exit.
#include <asm/ptrace.h>
#include <dlfcn.h>
#include <elf.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/memfd.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/ptrace.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <sys/wait.h>
#include <unistd.h>
#include <algorithm>
#include <array>
#include <vector>

#ifndef __aarch64__
#error "SukiSU standalone system_server injector requires arm64"
#endif

namespace {
constexpr size_t kStageBytes = 65536;
constexpr size_t kChunkBytes = 49152;

struct Trace {
    pid_t pid;
    user_pt_regs saved{};
    bool attached = false;
    bool stopped = false;
    bool savedValid = false;

    explicit Trace(pid_t target) : pid(target) {}
    bool attach() {
        if (ptrace(PTRACE_ATTACH, pid, nullptr, nullptr) != 0) {
            perror("PTRACE_ATTACH (check SELinux)");
            return false;
        }
        attached = true;
        int status = 0;
        pid_t got;
        do {
            got = waitpid(pid, &status, __WALL);
        } while (got == -1 && errno == EINTR);
        if (got != pid || !WIFSTOPPED(status)) return false;
        stopped = true;
        if (!regs(saved, false)) return false;
        savedValid = true;
        return true;
    }
    bool regs(user_pt_regs& value, bool set) const {
        struct iovec io{&value, sizeof(value)};
        return ptrace(set ? PTRACE_SETREGSET : PTRACE_GETREGSET,
                pid, reinterpret_cast<void*>(NT_PRSTATUS), &io) == 0;
    }
    bool put(uint64_t dest, const void* src, size_t n) const {
        struct iovec local{const_cast<void*>(src), n};
        struct iovec remote{reinterpret_cast<void*>(dest), n};
        ssize_t written = process_vm_writev(pid, &local, 1, &remote, 1, 0);
        if (written == static_cast<ssize_t>(n)) return true;
        const auto* bytes = reinterpret_cast<const uint8_t*>(src);
        for (size_t i = 0; i < n; i += sizeof(long)) {
            long word = 0;
            size_t count = std::min(sizeof(long), n - i);
            if (count < sizeof(long)) {
                errno = 0;
                word = ptrace(PTRACE_PEEKDATA, pid, reinterpret_cast<void*>(dest + i), nullptr);
                if (word == -1 && errno) return false;
            }
            memcpy(&word, bytes + i, count);
            if (ptrace(PTRACE_POKEDATA, pid, reinterpret_cast<void*>(dest + i),
                       reinterpret_cast<void*>(word)) != 0) return false;
        }
        return true;
    }
    bool call(uint64_t address, std::array<uint64_t, 6> args,
              uint64_t stack, uint64_t& result) {
        user_pt_regs before{};
        if (!stopped || !regs(before, false)) return false;
        user_pt_regs next = before;
        for (size_t i = 0; i < args.size(); i++) next.regs[i] = args[i];
        next.pc = address;
        next.regs[30] = 0; // Unmapped return PC stops the traced thread.
        next.sp = stack & ~15ULL;
        if (!regs(next, true)) return false;
        bool ok = false;
        if (ptrace(PTRACE_CONT, pid, nullptr, nullptr) == 0) {
            stopped = false;
            int status = 0;
            pid_t got;
            do {
                got = waitpid(pid, &status, __WALL);
            } while (got == -1 && errno == EINTR);
            if (got == pid && WIFSTOPPED(status)) {
                stopped = true;
                if (WSTOPSIG(status) == SIGSEGV) {
                    user_pt_regs after{};
                    if (regs(after, false) && after.pc < 0x1000) {
                        result = after.regs[0];
                        ok = true;
                    }
                }
            }
        }
        // Never overwrite a running tracee's registers. The destructor must
        // also avoid writing a zero-initialized snapshot after attach failure.
        if (!stopped || !regs(before, true)) return false;
        return ok;
    }
    ~Trace() {
        if (!attached) return;
        if (savedValid && stopped && !regs(saved, true)) {
            fprintf(stderr, "Could not restore original system_server registers\n");
        }
        if (ptrace(PTRACE_DETACH, pid, nullptr, nullptr) != 0) {
            perror("PTRACE_DETACH");
        }
    }
};

uint64_t remoteSymbol(pid_t pid, const char* symbol) {
    void* local = dlsym(RTLD_DEFAULT, symbol);
    Dl_info info{};
    if (!local || !dladdr(local, &info) || !info.dli_fname || !info.dli_fbase) {
        fprintf(stderr, "Cannot resolve local %s\n", symbol);
        return 0;
    }
    const char* baseName = strrchr(info.dli_fname, '/');
    baseName = baseName ? baseName + 1 : info.dli_fname;
    char maps[64];
    snprintf(maps, sizeof(maps), "/proc/%d/maps", pid);
    FILE* fp = fopen(maps, "r");
    if (!fp) return 0;
    uint64_t mapped = 0;
    char* line = nullptr;
    size_t cap = 0;
    while (getline(&line, &cap, fp) > 0) {
        unsigned long long begin = 0, end = 0, offset = 0;
        char perms[8] = {}, path[1024] = {};
        if (sscanf(line, "%llx-%llx %7s %llx %*s %*s %1023s",
                   &begin, &end, perms, &offset, path) != 5 || offset != 0) continue;
        const char* file = strrchr(path, '/');
        file = file ? file + 1 : path;
        if (strcmp(file, baseName) != 0) continue;
        mapped = static_cast<uint64_t>(begin);
        break;
    }
    free(line);
    fclose(fp);
    if (!mapped) {
        fprintf(stderr, "Cannot locate %s in target mappings\n", baseName);
        return 0;
    }
    return mapped + (reinterpret_cast<uintptr_t>(local) -
                     reinterpret_cast<uintptr_t>(info.dli_fbase));
}

// Fail closed when invoked directly with an unrelated privileged process.
// system_server is conventionally uid 1000; never accept another UID.
bool isExpectedTarget(pid_t pid) {
    char path[64];
    snprintf(path, sizeof(path), "/proc/%d/cmdline", pid);
    FILE* fp = fopen(path, "rb");
    if (!fp) {
        perror("Cannot open target cmdline");
        return false;
    }
    char name[128] = {};
    size_t length = fread(name, 1, sizeof(name) - 1, fp);
    fclose(fp);
    if (!length || strcmp(name, "system_server") != 0) {
        fprintf(stderr, "Refusing to inject into a process other than system_server\n");
        return false;
    }
    snprintf(path, sizeof(path), "/proc/%d", pid);
    struct stat info{};
    if (stat(path, &info) != 0 || info.st_uid != 1000) {
        fprintf(stderr, "Refusing to inject into a process not owned by Android system UID\n");
        return false;
    }
    return true;
}

bool loadPayload(const char* file, std::vector<uint8_t>& data) {
    FILE* fp = fopen(file, "rb");
    if (!fp) { perror(file); return false; }
    if (fseek(fp, 0, SEEK_END) || ftell(fp) < 0) {
        fclose(fp); return false;
    }
    long size = ftell(fp);
    if (size <= 0 || size > 16 * 1024 * 1024L || fseek(fp, 0, SEEK_SET)) {
        fclose(fp); return false;
    }
    data.resize(static_cast<size_t>(size));
    bool ok = fread(data.data(), 1, data.size(), fp) == data.size();
    fclose(fp);
    return ok;
}
}

int main(int argc, char** argv) {
    if (argc != 4) {
        fprintf(stderr, "usage: %s <system_server pid> <payload.so> <manager.apk>\n", argv[0]);
        return 2;
    }
    char* end = nullptr;
    long parsed = strtol(argv[1], &end, 10);
    if (*end || parsed <= 1 || parsed > INT32_MAX || getuid() != 0) {
        fprintf(stderr, "Invalid PID or injector is not root\n");
        return 2;
    }
    auto pid = static_cast<pid_t>(parsed);
    // The path is subsequently copied into an in-process staging mmap.
    // Bound it *before* writing to system_server's memory.
    if (strlen(argv[3]) > 4096 || !isExpectedTarget(pid)) return 2;
    std::vector<uint8_t> data;
    if (!loadPayload(argv[2], data)) return 3;
    for (const char* name : {"mmap", "memfd_create", "write", "dlopen",
                             "dlsym", "munmap", "close"}) {
        if (!remoteSymbol(pid, name)) return 4;
    }
    Trace trace(pid);
    if (!trace.attach()) return 5;
    uint64_t result = 0;
    uint64_t safeStack = trace.saved.sp - 8192;
    if (!trace.call(remoteSymbol(pid, "mmap"), {0, kStageBytes, PROT_READ | PROT_WRITE,
                    MAP_PRIVATE | MAP_ANONYMOUS, static_cast<uint64_t>(-1), 0},
                    safeStack, result)) return 6;
    uint64_t stage = result;
    if (!stage || stage == static_cast<uint64_t>(-1)) return 6;
    uint64_t stack = stage + kStageBytes - 32;
    int outcome = 7;
    do {
        constexpr char name[] = "hma_sukisu_payload";
        if (!trace.put(stage, name, sizeof(name))) break;
        if (!trace.call(remoteSymbol(pid, "memfd_create"),
                        {stage, MFD_CLOEXEC, 0, 0, 0, 0}, stack, result)) break;
        if (static_cast<int64_t>(result) < 0) break;
        uint64_t fd = result;
        bool copied = true;
        for (size_t offset = 0; offset < data.size(); offset += kChunkBytes) {
            size_t chunk = std::min(kChunkBytes, data.size() - offset);
            if (!trace.put(stage, data.data() + offset, chunk) ||
                !trace.call(remoteSymbol(pid, "write"),
                            {fd, stage, chunk, 0, 0, 0}, stack, result) ||
                result != chunk) { copied = false; break; }
        }
        if (copied) {
            char fdPath[64];
            snprintf(fdPath, sizeof(fdPath), "/proc/self/fd/%llu",
                     static_cast<unsigned long long>(fd));
            if (trace.put(stage, fdPath, strlen(fdPath) + 1) &&
                trace.call(remoteSymbol(pid, "dlopen"),
                           {stage, RTLD_NOW | RTLD_LOCAL, 0, 0, 0, 0},
                           stack, result) && result) {
                uint64_t handle = result;
                constexpr char method[] = "hma_bootstrap";
                if (trace.put(stage, method, sizeof(method)) &&
                    trace.call(remoteSymbol(pid, "dlsym"),
                               {handle, stage, 0, 0, 0, 0}, stack, result) && result) {
                    uint64_t bootstrap = result;
                    if (trace.put(stage, argv[3], strlen(argv[3]) + 1) &&
                        trace.call(bootstrap, {stage, 0, 0, 0, 0, 0}, stack, result)
                        && result == 0) {
                        outcome = 0;
                    }
                }
            }
        }
        trace.call(remoteSymbol(pid, "close"), {fd, 0, 0, 0, 0, 0}, stack, result);
    } while (false);
    trace.call(remoteSymbol(pid, "munmap"),
               {stage, kStageBytes, 0, 0, 0, 0}, safeStack, result);
    if (outcome) {
        fprintf(stderr, "Remote payload loading failed; thread context restored\n");
    }
    return outcome;
}
