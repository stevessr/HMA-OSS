// JNI bridge resident inside system_server; contains no Zygisk/Xposed APIs.
// JNI thread runs outside the dynamic linker's constructor lock.
#include <jni.h>
#include <android/log.h>
#include <dlfcn.h>
#include <pthread.h>
#include <cstdlib>
#include <cstring>
#include <memory>

namespace {
constexpr const char* TAG = "HMA-SukiSU";
using GetVMs = jint (*)(JavaVM**, jsize, jsize*);

void log(const char* message) {
    __android_log_write(ANDROID_LOG_INFO, TAG, message);
}
bool checked(JNIEnv* env, const char* phase) {
    if (!env->ExceptionCheck()) return true;
    __android_log_print(ANDROID_LOG_ERROR, TAG, "Java exception at %s", phase);
    env->ExceptionDescribe();
    env->ExceptionClear();
    return false;
}
void* startJava(void* arg) {
    std::unique_ptr<char, decltype(&free)> apk(static_cast<char*>(arg), free);
    void* art = dlopen("libart.so", RTLD_NOW | RTLD_NOLOAD);
    auto getVMs = reinterpret_cast<GetVMs>(
        dlsym(art ? art : RTLD_DEFAULT, "JNI_GetCreatedJavaVMs"));
    if (!getVMs) {
        log("Cannot locate process JavaVM");
        return nullptr;
    }
    JavaVM* vm = nullptr;
    jsize count = 0;
    if (getVMs(&vm, 1, &count) != JNI_OK || count != 1 || !vm) {
        log("Unexpected JavaVM count");
        return nullptr;
    }
    JNIEnv* env = nullptr;
    if (vm->AttachCurrentThread(reinterpret_cast<void**>(&env), nullptr) != JNI_OK) {
        log("AttachCurrentThread failed");
        return nullptr;
    }
    do {
        jclass base = env->FindClass("java/lang/ClassLoader");
        jmethodID system = base ?
            env->GetStaticMethodID(base, "getSystemClassLoader",
                                   "()Ljava/lang/ClassLoader;") : nullptr;
        jobject parent = system ? env->CallStaticObjectMethod(base, system) : nullptr;
        if (!checked(env, "system loader") || !parent) break;

        jclass dex = env->FindClass("dalvik/system/DexClassLoader");
        jmethodID ctor = dex ?
            env->GetMethodID(dex, "<init>",
                             "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Ljava/lang/ClassLoader;)V")
            : nullptr;
        jstring path = env->NewStringUTF(apk.get());
        jstring optim = env->NewStringUTF("/data/system");
        jobject loader = ctor ?
            env->NewObject(dex, ctor, path, optim, nullptr, parent) : nullptr;
        if (!checked(env, "create dex loader") || !loader) break;

        jmethodID load = env->GetMethodID(
            base, "loadClass", "(Ljava/lang/String;)Ljava/lang/Class;");
        jstring entryName = env->NewStringUTF(
            "org.frknkrc44.hma_oss.zygote.SukiStandaloneEntry");
        jobject entry = load ? env->CallObjectMethod(loader, load, entryName) : nullptr;
        if (!checked(env, "load Java entrypoint") || !entry) break;
        jmethodID start = env->GetStaticMethodID(
            static_cast<jclass>(entry), "start", "(Ljava/lang/ClassLoader;)V");
        if (!checked(env, "resolve start") || !start) break;
        env->CallStaticVoidMethod(static_cast<jclass>(entry), start, parent);
        if (!checked(env, "invoke start")) break;
        log("Standalone Java backend entrypoint invoked");
    } while (false);
    vm->DetachCurrentThread();
    return nullptr;
}
}

extern "C" __attribute__((visibility("default"))) int hma_bootstrap(const char* apk) {
    if (!apk || !apk[0] || strlen(apk) > 4096) return -1;
    char* path = strdup(apk);
    if (!path) return -1;
    pthread_t thread{};
    int rc = pthread_create(&thread, nullptr, startJava, path);
    if (rc != 0) {
        free(path);
        return -rc;
    }
    pthread_detach(thread);
    return 0;
}
